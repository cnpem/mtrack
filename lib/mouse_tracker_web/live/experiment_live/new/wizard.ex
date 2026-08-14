defmodule MouseTrackerWeb.ExperimentLive.New.Wizard do
  @moduledoc """
  Pure, socket-free wizard-state logic for `ExperimentLive.New`'s 3-step
  upload/ROI/review flow: per-video spec flags, scale/ROI reference
  resolution (a video either *is* a reference or inherits from one), step
  validation, px_per_10cm derivation from the 2 scale segments, and building
  the calibrations/rois payload for `Experiments.create_experiment_with_videos/2`.

  Everything here takes plain data (`assigns`, `specs`, `calibrations`, video
  maps) rather than `%Phoenix.LiveView.Socket{}`, so it can be tested directly
  without mounting a LiveView. Functions that mutate socket assigns (event
  handlers) stay in `ExperimentLive.New` and call into this module.
  """

  @divergence_warning_pct 8.0

  # --- Per-video spec (subject/reference/inherit-source flags) ---

  # `subject_id` pre-fills `subject_ref` as `{:existing, id}` when reusing a
  # library video that already had a subject attached — more likely than
  # "no subject" for a video the user is deliberately reusing.
  def default_spec(filename, subject_id \\ nil) do
    %{
      subject_ref:
        if(subject_id,
          do: {:existing, subject_id},
          else: {:new, Path.rootname(filename), nil}
        ),
      is_ref?: false,
      source: nil
    }
  end

  def default_cal(defaults) do
    %{
      valid_region: nil,
      scale: nil,
      scale_cm: "",
      scale2: nil,
      scale_cm2: "",
      threshold: defaults.threshold,
      min_area: defaults.min_area,
      peripheral_pct: defaults.peripheral_pct,
      immobility_threshold_cm: defaults.immobility_threshold_cm
    }
  end

  def is_ref?(%{is_ref?: v}), do: v
  def put_ref_flag(spec, v), do: %{spec | is_ref?: v}
  def source_of(%{source: s}), do: s
  def put_source(spec, s), do: %{spec | source: s}

  # --- Reference/inheritance resolution ---

  def live_refs(assigns) do
    Enum.filter(entry_refs(assigns), fn r -> assigns.specs[r] && is_ref?(assigns.specs[r]) end)
  end

  def entry_refs(assigns), do: Enum.map(assigns.saved_videos, & &1.ref)

  # Options for the reference dropdown: every video currently marked as a
  # reference, excluding the active video itself (it isn't a candidate for
  # its own dropdown, since inherit_control only renders for non-references).
  def source_options(assigns) do
    Enum.map(
      live_refs(assigns),
      &%{ref: &1, filename: ref_filename(&1, assigns.saved_videos)}
    )
  end

  def current_source_ref(spec) do
    case source_of(spec) do
      {:inherit, r} -> r
      _ -> nil
    end
  end

  def resolve_ref(ref, specs) do
    spec = specs[ref]

    cond do
      is_nil(spec) -> nil
      is_ref?(spec) -> ref
      match?({:inherit, _}, source_of(spec)) -> resolve_inherit(spec, specs)
      true -> nil
    end
  end

  defp resolve_inherit(spec, specs) do
    {:inherit, r} = source_of(spec)
    if specs[r] && is_ref?(specs[r]), do: r, else: nil
  end

  def resolve_label(ref, specs, videos) do
    case resolve_ref(ref, specs) do
      nil -> nil
      ^ref -> "★ reference"
      other -> "inherits from #{ref_filename(other, videos)}"
    end
  end

  def ref_filename(ref, videos) do
    case Enum.find(videos, &(&1.ref == ref)) do
      nil -> ref
      v -> v.filename
    end
  end

  def cal_field(calibrations, ref, key) do
    case Map.get(calibrations, ref) do
      nil -> nil
      cal -> Map.get(cal, key)
    end
  end

  def scale_status(calibrations, ref) do
    case Map.get(calibrations, ref) do
      %{} = cal ->
        case derive_px_per_10cm_pair(cal) do
          %{avg: avg, divergence_pct: pct} -> "px_per_10cm=#{avg} (div #{pct}%)"
          nil -> ""
        end

      _ ->
        ""
    end
  end

  # Whether a given required shape has already been drawn for a video's own
  # calibration — drives the checkmark shown inside its mode_button.
  def shape_done?(calibrations, ref, "valid_region"),
    do: not is_nil(cal_field(calibrations, ref, :valid_region))

  def shape_done?(calibrations, ref, "scale"),
    do: not is_nil(cal_field(calibrations, ref, :scale))

  def shape_done?(calibrations, ref, "scale2"),
    do: not is_nil(cal_field(calibrations, ref, :scale2))

  # --- Step validation ---

  def step1_valid?(assigns) do
    (assigns.saved_videos != [] or assigns.uploads.videos.entries != []) and
      Enum.all?(assigns.uploads.videos.entries, &(&1.progress == 100)) and
      Phoenix.Component.upload_errors(assigns.uploads.videos) == []
  end

  def step2_valid?(assigns) do
    refs = entry_refs(assigns)
    live = live_refs(assigns)
    roi_names = for r <- live, roi <- Map.get(assigns.rois, r, []), do: roi.name

    refs != [] and
      Enum.all?(refs, fn r ->
        case resolve_ref(r, assigns.specs) do
          nil -> false
          cal_ref -> cal_complete?(assigns.calibrations[cal_ref])
        end
      end) and
      Enum.all?(live, fn r ->
        Enum.all?(Map.get(assigns.rois, r, []), &present?(&1.name))
      end) and
      Enum.all?(roi_names, &present?/1)
  end

  # Human-readable breakdown of step2_valid?/1, shown next to the disabled
  # Continue button so an unmet condition (e.g. an unnamed ROI) is visible
  # instead of silently blocking navigation.
  def step2_missing_reasons(assigns) do
    videos = assigns.saved_videos
    refs = entry_refs(assigns)
    live = live_refs(assigns)

    cal_msgs =
      for r <- refs,
          cal_ref = resolve_ref(r, assigns.specs),
          is_nil(cal_ref) or not cal_complete?(assigns.calibrations[cal_ref]) do
        "#{ref_filename(r, videos)}: scale/valid region incomplete"
      end

    roi_name_msgs =
      for r <- live,
          roi <- Map.get(assigns.rois, r, []),
          not present?(roi.name) do
        "#{ref_filename(r, videos)}: one ROI zone is missing a name"
      end

    # Duplicate ROI names are intentional now — two recordings of the "same"
    # zone (camera nudged between sessions) share a name so they land in the
    # same exported column. So no uniqueness check here.
    (cal_msgs ++ roi_name_msgs) |> Enum.uniq()
  end

  def cal_complete?(nil), do: false

  def cal_complete?(%{valid_region: vr, scale: s1, scale_cm: cm1, scale2: s2, scale_cm2: cm2}) do
    not is_nil(vr) and
      not is_nil(s1) and parse_float(cm1) > 0 and
      not is_nil(s2) and parse_float(cm2) > 0
  end

  def present?(nil), do: false
  def present?(v) when is_binary(v), do: String.trim(v) != ""
  def present?(_), do: true

  def parse_float(v) when is_number(v), do: v * 1.0

  def parse_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  def parse_float(_), do: 0.0

  def parse_subject_ref("new", name, group) do
    case String.trim(name || "") do
      "" -> {:new, "", normalize_group(group)}
      n -> {:new, n, normalize_group(group)}
    end
  end

  def parse_subject_ref("", _name, _group), do: nil
  def parse_subject_ref(id_str, _name, _group), do: {:existing, String.to_integer(id_str)}

  defp normalize_group(nil), do: nil

  defp normalize_group(g) do
    case String.trim(g) do
      "" -> nil
      t -> t
    end
  end

  def subject_new_name({:new, name, _group}), do: name
  def subject_new_name(_), do: nil

  def subject_new_group({:new, _name, group}), do: group
  def subject_new_group(_), do: nil

  # --- px_per_10cm derivation ---

  def divergence_warning_pct, do: @divergence_warning_pct

  def derive_px_per_10cm(%{x1: x1, y1: y1, x2: x2, y2: y2}, cm_str) do
    dist = :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2))

    case parse_float(cm_str) do
      cm when cm > 0 -> Float.round(dist / cm * 10, 4)
      _ -> 0.0
    end
  end

  # Combines both scale segments into one px_per_10cm (their average) plus the
  # relative divergence between them, for the non-blocking warning banner.
  # Returns nil when either segment isn't fully drawn/measured yet.
  def derive_px_per_10cm_pair(%{scale: s1, scale_cm: cm1, scale2: s2, scale_cm2: cm2})
      when not is_nil(s1) and not is_nil(s2) do
    px1 = derive_px_per_10cm(s1, cm1)
    px2 = derive_px_per_10cm(s2, cm2)

    if px1 > 0 and px2 > 0 do
      avg = (px1 + px2) / 2

      %{
        px1: px1,
        px2: px2,
        avg: Float.round(avg, 4),
        divergence_pct: Float.round(abs(px1 - px2) / avg * 100, 2)
      }
    end
  end

  def derive_px_per_10cm_pair(_cal), do: nil

  # --- Create payload ---

  def build_calibrations(assigns) do
    for ref <- live_refs(assigns), into: %{} do
      cal = assigns.calibrations[ref]
      vr = cal.valid_region
      s1 = cal.scale
      s2 = cal.scale2
      summary = derive_px_per_10cm_pair(cal) || %{avg: 0.0}

      params = %{
        "cage_side_cm" => cal.scale_cm,
        "scale_cm_2" => cal.scale_cm2,
        "px_per_10cm" => summary.avg,
        "threshold" => cal.threshold,
        "min_area" => cal.min_area,
        "peripheral_pct" => cal.peripheral_pct,
        "immobility_threshold_cm" => cal.immobility_threshold_cm,
        "valid_region_x" => vr.x,
        "valid_region_y" => vr.y,
        "valid_region_w" => vr.w,
        "valid_region_h" => vr.h,
        "coordinate_x1" => s1.x1,
        "coordinate_y1" => s1.y1,
        "coordinate_x2" => s1.x2,
        "coordinate_y2" => s1.y2,
        "coordinate_x3" => s2.x1,
        "coordinate_y3" => s2.y1,
        "coordinate_x4" => s2.x2,
        "coordinate_y4" => s2.y2
      }

      {ref, params}
    end
  end

  def build_rois(assigns) do
    for ref <- live_refs(assigns), into: %{} do
      {ref, Enum.map(Map.get(assigns.rois, ref, []), &roi_to_params/1)}
    end
  end

  def roi_to_params(%{shape: "circle", name: name, cx: cx, cy: cy, r: r}) do
    %{"name" => name, "shape" => "circle", "x" => cx, "y" => cy, "radius" => r}
  end

  def roi_to_params(%{shape: "polygon", name: name, points: [x0, y0, x1, y1, x2, y2, x3, y3]}) do
    %{
      "name" => name,
      "shape" => "polygon",
      "x" => x0,
      "y" => y0,
      "x1" => x0,
      "y1" => y0,
      "x2" => x1,
      "y2" => y1,
      "x3" => x2,
      "y3" => y2,
      "x4" => x3,
      "y4" => y3
    }
  end

  # --- Misc ---

  def experiment_name(name, saved_videos) do
    case String.trim(name || "") do
      "" ->
        saved_videos
        |> List.first()
        |> then(&((&1 && Path.rootname(&1.filename)) || "Untitled experiment"))

      n ->
        n
    end
  end

  def default_name_placeholder(saved_videos) do
    case saved_videos do
      [first | _] -> Path.rootname(first.filename)
      _ -> "My experiment"
    end
  end

  # Clamp to [0, frame_count - 1] when the frame count is known, else just floor
  # at 0 (an out-of-range seek simply reads nothing and falls to the error path).
  def clamp_frame(n, video) do
    case Map.get(video, :frame_count) do
      count when is_integer(count) and count > 0 -> n |> max(0) |> min(count - 1)
      _ -> max(n, 0)
    end
  end
end
