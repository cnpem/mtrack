defmodule MouseTrackerWeb.ExperimentLive.New do
  @moduledoc """
  Three-step experiment-creation wizard (upload → ROI & scale → review),
  implemented as a single LiveView whose `live_action` (`:upload | :roi |
  :review`) selects the step. Navigating between steps uses `push_patch`, so the
  one process keeps its `allow_upload` and all wizard state across steps.

  Step 2 is fully visual: the first frame of each uploaded video is shown and the
  user draws the valid region (box), a scale reference (2-point segment + real
  cm, from which `px_per_10cm` is derived) and ROIs (4-point polygon or circle)
  on it, via the `RoiCanvas` JS hook. Because the uploaded file is only readable
  inside `consume_uploaded_entries`, videos are saved to disk (and their first
  frame extracted) when entering step 2, not at create time.

  ROI and scale follow a *reference* model: any video can be a ROI and/or scale
  reference; other videos inherit from one, and clicking cycles through the
  available references. Scale must resolve for every video (the pipeline needs a
  `valid_region` + `px_per_10cm`); ROIs are optional.
  """
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments
  alias MouseTracker.Tracking.FrameExtractor

  # Two independent scale segments are required so px_per_10cm is the average
  # of two measurements instead of a single click-prone one; divergence above
  # this only warns (non-blocking) — it doesn't gate wizard navigation.
  @divergence_warning_pct 8.0

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New experiment")
     |> assign(:step, :upload)
     |> assign(:mode, :batch)
     |> assign(:upload_token, Ecto.UUID.generate())
     |> assign(:saved_videos, [])
     |> assign(:specs, %{})
     |> assign(:calibrations, %{})
     |> assign(:rois, %{})
     |> assign(:active_ref, nil)
     |> assign(:draw_mode, "roi_polygon")
     |> assign(:experiment_name, "")
     |> allow_upload(:videos,
       accept: ~w(.mp4 .avi .mov),
       max_entries: 20,
       max_file_size: 4_000_000_000,
       auto_upload: true
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    step = socket.assigns.live_action
    socket = assign(socket, :step, step)

    socket =
      cond do
        step in [:roi, :review] and socket.assigns.saved_videos == [] ->
          push_patch(socket, to: ~p"/experiments/new")

        step == :review and not step2_valid?(socket.assigns) ->
          socket
          |> put_flash(:error, "Complete ROI & scale first.")
          |> push_patch(to: ~p"/experiments/new/roi")

        true ->
          socket
      end

    {:noreply, socket}
  end

  # --- Upload step events ---

  @impl true
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :videos, ref)}
  end

  def handle_event("remove_saved", %{"ref" => ref}, socket) do
    {:noreply, remove_saved_video(socket, ref)}
  end

  def handle_event("set_mode", %{"mode" => mode}, socket) do
    mode = String.to_existing_atom(mode)

    socket =
      if mode == :single do
        case socket.assigns.uploads.videos.entries do
          [_keep | rest] ->
            Enum.reduce(rest, socket, fn e, s -> cancel_upload(s, :videos, e.ref) end)

          _ ->
            socket
        end
      else
        socket
      end

    {:noreply, assign(socket, :mode, mode)}
  end

  # Continue → save completed uploads (video file + first-frame PNG), then patch.
  def handle_event("goto", %{"step" => "roi"}, socket) do
    socket = save_pending_uploads(socket)
    {:noreply, push_patch(socket, to: ~p"/experiments/new/roi")}
  end

  def handle_event("goto", %{"step" => step}, socket) do
    path =
      case step do
        "upload" -> ~p"/experiments/new"
        "review" -> ~p"/experiments/new/review"
      end

    {:noreply, push_patch(socket, to: path)}
  end

  # --- ROI & scale step events ---

  def handle_event("select_active", %{"ref" => ref}, socket) do
    {:noreply, assign(socket, :active_ref, ref)}
  end

  def handle_event("set_draw_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :draw_mode, mode)}
  end

  def handle_event("toggle_cal_ref", %{"ref" => ref}, socket) do
    {:noreply, toggle_ref(socket, ref, :cal)}
  end

  def handle_event("toggle_roi_ref", %{"ref" => ref}, socket) do
    {:noreply, toggle_ref(socket, ref, :roi)}
  end

  def handle_event("cycle_cal_source", %{"ref" => ref}, socket) do
    {:noreply, cycle_source(socket, ref, :cal)}
  end

  def handle_event("cycle_roi_source", %{"ref" => ref}, socket) do
    {:noreply, cycle_source(socket, ref, :roi)}
  end

  def handle_event("shape_drawn", shape, socket) do
    {:noreply, apply_shape(socket, shape)}
  end

  def handle_event("set_scale_cm", %{"value" => value}, socket) do
    {:noreply, update_calibration(socket, socket.assigns.active_ref, &%{&1 | scale_cm: value})}
  end

  def handle_event("set_scale_cm2", %{"value" => value}, socket) do
    {:noreply, update_calibration(socket, socket.assigns.active_ref, &%{&1 | scale_cm2: value})}
  end

  def handle_event("cal_setting", %{"threshold" => th, "min_area" => ma}, socket) do
    {:noreply,
     update_calibration(socket, socket.assigns.active_ref, &%{&1 | threshold: th, min_area: ma})}
  end

  def handle_event("set_roi_name", %{"index" => idx, "value" => value}, socket) do
    ref = socket.assigns.active_ref
    i = String.to_integer(idx)

    list =
      socket.assigns.rois |> Map.get(ref, []) |> List.update_at(i, &Map.put(&1, :name, value))

    {:noreply, assign(socket, :rois, Map.put(socket.assigns.rois, ref, list))}
  end

  def handle_event("remove_roi", %{"index" => idx}, socket) do
    ref = socket.assigns.active_ref
    list = socket.assigns.rois |> Map.get(ref, []) |> List.delete_at(String.to_integer(idx))
    {:noreply, assign(socket, :rois, Map.put(socket.assigns.rois, ref, list))}
  end

  # --- Review step events ---

  def handle_event("update_review", params, socket) do
    specs =
      Enum.reduce(params["subject"] || %{}, socket.assigns.specs, fn {ref, name}, acc ->
        case acc do
          %{^ref => spec} -> Map.put(acc, ref, %{spec | subject_name: name})
          _ -> acc
        end
      end)

    {:noreply,
     socket
     |> assign(:specs, specs)
     |> assign(:experiment_name, params["experiment_name"] || socket.assigns.experiment_name)}
  end

  def handle_event("create", _params, socket) do
    if step2_valid?(socket.assigns) do
      do_create(socket)
    else
      {:noreply, put_flash(socket, :error, "Complete ROI & scale first.")}
    end
  end

  # --- Saving uploads + frame extraction ---

  defp save_pending_uploads(socket) do
    token = socket.assigns.upload_token

    consumed =
      consume_uploaded_entries(socket, :videos, fn %{path: tmp}, entry ->
        video_dir = Path.join([static_dir(), "uploads", "videos", token])
        frame_dir = Path.join([static_dir(), "uploads", "frames", token])
        File.mkdir_p!(video_dir)

        filepath = Path.join(video_dir, "#{entry.ref}-#{entry.client_name}")
        File.cp!(tmp, filepath)

        frame_path = Path.join(frame_dir, "#{entry.ref}.png")

        frame_url =
          frame_result(FrameExtractor.extract_first_frame(filepath, frame_path), token, entry.ref)

        {:ok,
         %{
           ref: entry.ref,
           filename: entry.client_name,
           filepath: filepath,
           frame_url: frame_url
         }}
      end)

    saved = socket.assigns.saved_videos ++ consumed

    specs =
      Enum.reduce(consumed, socket.assigns.specs, fn v, acc ->
        Map.put_new(acc, v.ref, default_spec(v.filename))
      end)

    active = socket.assigns.active_ref || saved |> List.first() |> then(&(&1 && &1.ref))

    socket
    |> assign(:saved_videos, saved)
    |> assign(:specs, specs)
    |> assign(:active_ref, active)
  end

  defp frame_result(:ok, token, ref), do: "/uploads/frames/#{token}/#{ref}.png"
  defp frame_result({:error, _}, _token, _ref), do: nil

  defp remove_saved_video(socket, ref) do
    saved = Enum.reject(socket.assigns.saved_videos, &(&1.ref == ref))

    Enum.filter(socket.assigns.saved_videos, &(&1.ref == ref))
    |> Enum.each(fn v ->
      File.rm(v.filepath)

      File.rm(
        Path.join([static_dir(), "uploads", "frames", socket.assigns.upload_token, "#{ref}.png"])
      )
    end)

    active =
      if socket.assigns.active_ref == ref,
        do: saved |> List.first() |> then(&(&1 && &1.ref)),
        else: socket.assigns.active_ref

    socket
    |> assign(:saved_videos, saved)
    |> assign(:specs, Map.delete(socket.assigns.specs, ref))
    |> assign(:calibrations, Map.delete(socket.assigns.calibrations, ref))
    |> assign(:rois, Map.delete(socket.assigns.rois, ref))
    |> assign(:active_ref, active)
  end

  # --- Applying drawn shapes ---

  defp apply_shape(socket, %{"kind" => "valid_region", "x" => x, "y" => y, "w" => w, "h" => h}) do
    if active_flag?(socket, :cal) do
      update_calibration(
        socket,
        socket.assigns.active_ref,
        &%{&1 | valid_region: %{x: x, y: y, w: w, h: h}}
      )
    else
      socket
    end
  end

  defp apply_shape(socket, %{"kind" => "scale", "x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}) do
    if active_flag?(socket, :cal) do
      update_calibration(
        socket,
        socket.assigns.active_ref,
        &%{&1 | scale: %{x1: x1, y1: y1, x2: x2, y2: y2}}
      )
    else
      socket
    end
  end

  defp apply_shape(socket, %{"kind" => "scale2", "x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}) do
    if active_flag?(socket, :cal) do
      update_calibration(
        socket,
        socket.assigns.active_ref,
        &%{&1 | scale2: %{x1: x1, y1: y1, x2: x2, y2: y2}}
      )
    else
      socket
    end
  end

  defp apply_shape(socket, %{"kind" => "roi_polygon", "points" => points}) do
    add_roi(socket, %{shape: "polygon", name: nil, points: points})
  end

  defp apply_shape(socket, %{"kind" => "roi_circle", "cx" => cx, "cy" => cy, "r" => r}) do
    add_roi(socket, %{shape: "circle", name: nil, cx: cx, cy: cy, r: r})
  end

  defp apply_shape(socket, _), do: socket

  defp add_roi(socket, roi) do
    if active_flag?(socket, :roi) do
      ref = socket.assigns.active_ref
      list = Map.get(socket.assigns.rois, ref, [])
      roi = %{roi | name: "Zone #{length(list) + 1}"}
      assign(socket, :rois, Map.put(socket.assigns.rois, ref, list ++ [roi]))
    else
      socket
    end
  end

  defp active_flag?(socket, kind) do
    spec = socket.assigns.specs[socket.assigns.active_ref]
    spec && ref_flag(spec, kind)
  end

  defp update_calibration(socket, ref, fun) do
    cal = fun.(Map.get(socket.assigns.calibrations, ref, default_cal()))
    assign(socket, :calibrations, Map.put(socket.assigns.calibrations, ref, cal))
  end

  # --- Create ---

  defp do_create(socket) do
    specs = socket.assigns.specs

    payload = %{
      name: experiment_name(socket.assigns.experiment_name, socket.assigns.saved_videos),
      calibrations: build_calibrations(socket),
      rois: build_rois(socket),
      videos:
        Enum.map(socket.assigns.saved_videos, fn v ->
          %{
            filename: v.filename,
            filepath: v.filepath,
            subject_name: specs[v.ref].subject_name,
            cal_ref: resolve_ref(v.ref, specs, :cal),
            roi_ref: resolve_ref(v.ref, specs, :roi)
          }
        end)
    }

    case Experiments.create_experiment_with_videos(socket.assigns.current_scope, payload) do
      {:ok, {experiment, videos}} ->
        Enum.each(videos, &Experiments.enqueue_video_processing(&1.id))

        {:noreply,
         socket
         |> put_flash(:info, "Experiment created — processing started.")
         |> push_navigate(to: ~p"/experiments/#{experiment.id}")}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not create the experiment. Check the drawn regions and try again."
         )}
    end
  end

  defp build_calibrations(socket) do
    for ref <- live_refs(socket.assigns, :cal), into: %{} do
      cal = socket.assigns.calibrations[ref]
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

  defp build_rois(socket) do
    for ref <- live_refs(socket.assigns, :roi), into: %{} do
      {ref, Enum.map(Map.get(socket.assigns.rois, ref, []), &roi_to_params/1)}
    end
  end

  defp roi_to_params(%{shape: "circle", name: name, cx: cx, cy: cy, r: r}) do
    %{"name" => name, "shape" => "circle", "x" => cx, "y" => cy, "radius" => r}
  end

  defp roi_to_params(%{shape: "polygon", name: name, points: [x0, y0, x1, y1, x2, y2, x3, y3]}) do
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

  defp derive_px_per_10cm(%{x1: x1, y1: y1, x2: x2, y2: y2}, cm_str) do
    dist = :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2))

    case parse_float(cm_str) do
      cm when cm > 0 -> Float.round(dist / cm * 10, 4)
      _ -> 0.0
    end
  end

  # Combines both scale segments into one px_per_10cm (their average) plus the
  # relative divergence between them, for the non-blocking warning banner.
  # Returns nil when either segment isn't fully drawn/measured yet.
  defp derive_px_per_10cm_pair(%{scale: s1, scale_cm: cm1, scale2: s2, scale_cm2: cm2})
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

  defp derive_px_per_10cm_pair(_cal), do: nil

  defp divergence_warning_pct, do: @divergence_warning_pct

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={:experiments}
      breadcrumb="Workspace"
      page_title="New experiment"
    >
      <div class={[
        "mx-auto",
        @step == :roi && "max-w-[1180px]",
        @step != :roi && "max-w-[760px]"
      ]}>
        <.link
          navigate={~p"/experiments"}
          class="inline-flex items-center gap-1 text-[12.5px] text-[#667085] hover:text-[#0f1729]"
        >
          <.icon name="hero-chevron-left-micro" class="size-4" /> Experiments
        </.link>

        <div class="mt-3 text-[11px] font-semibold uppercase tracking-wide text-[#CC5500]">
          New experiment · Step {step_number(@step)} of 3
        </div>
        <h1 class="mt-1 text-[23px] font-bold text-[#0f1729]">{step_title(@step)}</h1>

        <div class="mt-6">
          <.upload_step :if={@step == :upload} {assigns} />
          <.roi_step :if={@step == :roi} {assigns} />
          <.review_step :if={@step == :review} {assigns} />
        </div>
      </div>
    </Layouts.locomo>
    """
  end

  # --- Step 1: Upload ---

  defp upload_step(assigns) do
    ~H"""
    <div class="inline-flex items-center gap-1 rounded-[9px] border border-[#e7e9ee] bg-white p-1">
      <button
        :for={{value, label} <- [{:single, "Single video"}, {:batch, "Batch"}]}
        type="button"
        phx-click="set_mode"
        phx-value-mode={value}
        class={[
          "rounded-[6px] px-3 py-1.5 text-[12.5px] font-medium transition-colors",
          @mode == value && "bg-[#1a212e] text-white",
          @mode != value && "text-[#667085] hover:text-[#0f1729]"
        ]}
      >
        {label}
      </button>
    </div>

    <form phx-change="validate_upload" phx-submit="validate_upload" class="mt-4">
      <label
        phx-drop-target={@uploads.videos.ref}
        class="flex cursor-pointer flex-col items-center justify-center rounded-[13px] border-2 border-dashed border-[#cdd2da] bg-white px-6 py-12 text-center transition-colors hover:border-[#CC5500] hover:bg-[#fdf6f0]"
      >
        <div class="flex size-11 items-center justify-center rounded-full bg-[#fbeee4] text-[#CC5500]">
          <.icon name="hero-arrow-up-tray" class="size-5" />
        </div>
        <div class="mt-3 text-[13.5px] text-[#344054]">
          Arraste vídeos aqui, ou <span class="font-semibold text-[#CC5500]">navegue</span>
        </div>
        <div class="mt-1 font-data text-[11.5px] text-[#98a2b3]">
          MP4 · AVI · MOV — até 4 GB — 30–60 fps
        </div>
        <.live_file_input upload={@uploads.videos} class="sr-only" />
      </label>
    </form>

    <div :for={err <- upload_errors(@uploads.videos)} class="mt-2 text-[12px] text-[#b42318]">
      {upload_error_to_string(err)}
    </div>

    <div :if={@saved_videos != [] or @uploads.videos.entries != []} class="mt-4 space-y-2">
      <div
        :for={v <- @saved_videos}
        class="flex items-center gap-3 rounded-[10px] border border-[#e7e9ee] bg-white p-3"
      >
        <div class="flex size-9 shrink-0 items-center justify-center rounded-[8px] bg-[#11161f] text-white/80">
          <.icon name="hero-play-solid" class="size-4" />
        </div>
        <div class="min-w-0 flex-1 truncate font-data text-[12.5px] font-medium text-[#0f1729]">
          {v.filename}
        </div>
        <span class="inline-flex items-center gap-1 rounded-[6px] bg-[#fbeee4] px-2 py-0.5 text-[10.5px] font-semibold text-[#b34a00]">
          <.icon name="hero-check-micro" class="size-3.5" /> saved
        </span>
        <button
          type="button"
          phx-click="remove_saved"
          phx-value-ref={v.ref}
          class="text-[#98a2b3] hover:text-[#b42318]"
          aria-label="Remove"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>

      <div
        :for={entry <- @uploads.videos.entries}
        class="flex items-center gap-3 rounded-[10px] border border-[#e7e9ee] bg-white p-3"
      >
        <div class="flex size-9 shrink-0 items-center justify-center rounded-[8px] bg-[#11161f] text-white/80">
          <.icon name="hero-play-solid" class="size-4" />
        </div>
        <div class="min-w-0 flex-1">
          <div class="truncate font-data text-[12.5px] font-medium text-[#0f1729]">
            {entry.client_name}
          </div>
          <div class="mt-1 flex items-center gap-2">
            <div class="h-1.5 flex-1 overflow-hidden rounded-full bg-[#f2f4f7]">
              <div class="h-full rounded-full bg-[#CC5500]" style={"width:#{entry.progress}%"}></div>
            </div>
            <span class="font-data text-[10.5px] text-[#98a2b3]">{entry.progress}%</span>
          </div>
          <div
            :for={err <- upload_errors(@uploads.videos, entry)}
            class="mt-1 text-[11px] text-[#b42318]"
          >
            {upload_error_to_string(err)}
          </div>
        </div>
        <button
          type="button"
          phx-click="cancel_upload"
          phx-value-ref={entry.ref}
          class="text-[#98a2b3] hover:text-[#b42318]"
          aria-label="Remove"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>

    <div class="mt-6 flex items-center justify-between">
      <.link
        navigate={~p"/experiments"}
        class="rounded-[8px] border border-[#e7e9ee] px-4 py-2.5 text-[13px] font-semibold text-[#344054] hover:border-[#d4d8df]"
      >
        Cancel
      </.link>
      <button
        type="button"
        phx-click="goto"
        phx-value-step="roi"
        disabled={not step1_valid?(assigns)}
        class="rounded-[8px] bg-[#CC5500] px-4 py-2.5 text-[13px] font-semibold text-white hover:bg-[#b34a00] disabled:cursor-not-allowed disabled:opacity-40"
      >
        Continue → ROI & scale
      </button>
    </div>
    """
  end

  # --- Step 2: ROI & scale (visual) ---

  defp roi_step(assigns) do
    active = assigns.active_ref

    assigns =
      assign(assigns,
        active_video: Enum.find(assigns.saved_videos, &(&1.ref == active)),
        active_spec: assigns.specs[active],
        active_rois: Map.get(assigns.rois, active, []),
        scale_summary:
          assigns.calibrations[active] && derive_px_per_10cm_pair(assigns.calibrations[active])
      )

    ~H"""
    <div class="grid grid-cols-1 gap-5 lg:grid-cols-[1.5fr_1fr]">
      <div>
        <div
          :if={@active_video && @active_video.frame_url}
          id="roi-canvas"
          phx-hook="RoiCanvas"
          data-frame={@active_video.frame_url}
          data-mode={@draw_mode}
          data-shapes={Jason.encode!(canvas_shapes(assigns))}
          class="relative overflow-hidden rounded-[10px] border border-[#e7e9ee] bg-[#11161f]"
        >
          <img data-role="frame" src={@active_video.frame_url} class="block w-full select-none" />
          <canvas data-role="overlay" class="absolute inset-0 h-full w-full cursor-crosshair"></canvas>
        </div>
        <div
          :if={@active_video && !@active_video.frame_url}
          class="flex h-64 items-center justify-center rounded-[10px] border border-dashed border-[#d4d8df] text-center font-data text-[12px] text-[#98a2b3]"
        >
          Could not extract a frame from this video.
        </div>

        <div :if={@active_spec} class="mt-3 flex flex-wrap gap-2">
          <button
            type="button"
            phx-click="toggle_cal_ref"
            phx-value-ref={@active_ref}
            class={ref_toggle_class(@active_spec.cal_ref?)}
          >
            <.icon name="hero-star-micro" class="size-4" />
            {if @active_spec.cal_ref?,
              do: "★ referência de escala",
              else: "usar como referência de escala"}
          </button>
          <button
            type="button"
            phx-click="toggle_roi_ref"
            phx-value-ref={@active_ref}
            class={ref_toggle_class(@active_spec.roi_ref?)}
          >
            <.icon name="hero-star-micro" class="size-4" />
            {if @active_spec.roi_ref?, do: "★ referência de ROI", else: "usar como referência de ROI"}
          </button>
        </div>
      </div>

      <div class="space-y-4">
        <div
          :if={@active_spec && @active_spec.cal_ref?}
          class="rounded-[13px] border border-[#e7e9ee] bg-white p-[16px]"
        >
          <div class="text-[12px] font-bold text-[#0f1729]">Escala & região válida</div>
          <div class="mt-2 flex flex-wrap gap-1.5">
            <.mode_button current={@draw_mode} mode="valid_region" label="Região válida" />
            <.mode_button current={@draw_mode} mode="scale" label="Escala 1 (2 pts)" />
            <.mode_button current={@draw_mode} mode="scale2" label="Escala 2 (2 pts)" />
          </div>
          <form
            id={"scale-cm-#{@active_ref}"}
            phx-change="set_scale_cm"
            phx-submit="set_scale_cm"
            class="mt-3"
          >
            <label class="text-[11px] text-[#667085]">Medida real da referência 1 (cm)</label>
            <input
              type="number"
              step="any"
              name="value"
              value={cal_field(@calibrations, @active_ref, :scale_cm)}
              placeholder="ex: 40"
              class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2.5 py-1.5 font-data text-[12.5px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
            />
          </form>
          <form
            id={"scale-cm2-#{@active_ref}"}
            phx-change="set_scale_cm2"
            phx-submit="set_scale_cm2"
            class="mt-3"
          >
            <label class="text-[11px] text-[#667085]">Medida real da referência 2 (cm)</label>
            <input
              type="number"
              step="any"
              name="value"
              value={cal_field(@calibrations, @active_ref, :scale_cm2)}
              placeholder="ex: 40"
              class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2.5 py-1.5 font-data text-[12.5px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
            />
          </form>
          <div class="mt-2 font-data text-[11px] text-[#8a93a3]">
            {scale_status(@calibrations, @active_ref)}
          </div>
          <div
            :if={@scale_summary && @scale_summary.divergence_pct > divergence_warning_pct()}
            class="mt-2 rounded-[8px] border border-[#fde68a] bg-[#fffbeb] p-2.5"
          >
            <div class="text-[11.5px] font-semibold text-[#92400e]">
              As duas medidas de escala divergem {@scale_summary.divergence_pct}% (esperado ≤{divergence_warning_pct()}%). Confira os pontos clicados em cada segmento.
            </div>
          </div>
          <form
            id={"cal-setting-#{@active_ref}"}
            phx-change="cal_setting"
            phx-submit="cal_setting"
            class="mt-3 grid grid-cols-2 gap-2"
          >
            <label class="block">
              <span class="text-[11px] text-[#667085]">Threshold</span>
              <input
                type="number"
                name="threshold"
                value={cal_field(@calibrations, @active_ref, :threshold)}
                class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2 py-1.5 font-data text-[12px] focus:border-[#CC5500] focus:outline-none"
              />
            </label>
            <label class="block">
              <span class="text-[11px] text-[#667085]">Min area</span>
              <input
                type="number"
                name="min_area"
                value={cal_field(@calibrations, @active_ref, :min_area)}
                class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2 py-1.5 font-data text-[12px] focus:border-[#CC5500] focus:outline-none"
              />
            </label>
          </form>
        </div>

        <div :if={@active_spec && not @active_spec.cal_ref?}>
          <.inherit_control
            kind="escala"
            resolved={resolve_label(@active_ref, @specs, :cal, @saved_videos)}
            event="cycle_cal_source"
            ref={@active_ref}
          />
        </div>

        <div
          :if={@active_spec && @active_spec.roi_ref?}
          class="rounded-[13px] border border-[#e7e9ee] bg-white p-[16px]"
        >
          <div class="text-[12px] font-bold text-[#0f1729]">ROIs (zonas)</div>
          <div class="mt-2 flex flex-wrap gap-1.5">
            <.mode_button current={@draw_mode} mode="roi_polygon" label="Polígono (4 pts)" />
            <.mode_button current={@draw_mode} mode="roi_circle" label="Círculo" />
          </div>
          <ul class="mt-3 space-y-2">
            <li :for={{roi, idx} <- Enum.with_index(@active_rois)} class="flex items-center gap-2">
              <span class="font-data text-[10.5px] uppercase text-[#98a2b3]">{roi.shape}</span>
              <form
                id={"roi-name-#{@active_ref}-#{idx}"}
                phx-change="set_roi_name"
                phx-submit="set_roi_name"
                class="flex-1"
              >
                <input type="hidden" name="index" value={idx} />
                <input
                  type="text"
                  name="value"
                  value={roi.name}
                  placeholder="Zone name"
                  class="w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2 py-1.5 font-data text-[12px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
                />
              </form>
              <button
                type="button"
                phx-click="remove_roi"
                phx-value-index={idx}
                class="text-[#98a2b3] hover:text-[#b42318]"
                aria-label="Remove ROI"
              >
                <.icon name="hero-trash-micro" class="size-4" />
              </button>
            </li>
          </ul>
          <div :if={@active_rois == []} class="mt-2 text-[11.5px] text-[#98a2b3]">
            Escolha um modo acima e desenhe no frame para adicionar zonas.
          </div>
        </div>

        <div :if={@active_spec && not @active_spec.roi_ref?}>
          <.inherit_control
            kind="ROI"
            resolved={resolve_label(@active_ref, @specs, :roi, @saved_videos)}
            event="cycle_roi_source"
            ref={@active_ref}
          />
        </div>

        <div>
          <div class="text-[11px] font-semibold uppercase tracking-wide text-[#98a2b3]">
            Vídeos deste batch
          </div>
          <ul class="mt-2 space-y-1.5">
            <li
              :for={v <- @saved_videos}
              phx-click="select_active"
              phx-value-ref={v.ref}
              class={[
                "cursor-pointer rounded-[10px] border bg-white p-2.5 transition-colors",
                v.ref == @active_ref && "border-[#CC5500] ring-1 ring-[#CC5500]/20",
                v.ref != @active_ref && "border-[#e7e9ee] hover:border-[#d4d8df]"
              ]}
            >
              <div class="truncate font-data text-[12px] font-medium text-[#0f1729]">
                {v.filename}
              </div>
              <div class="mt-1 flex flex-wrap gap-1.5">
                <.resource_badge
                  label="Escala"
                  tag={resolve_label(v.ref, @specs, :cal, @saved_videos)}
                />
                <.resource_badge
                  label="ROI"
                  tag={resolve_label(v.ref, @specs, :roi, @saved_videos)}
                  optional
                />
              </div>
            </li>
          </ul>
        </div>
      </div>
    </div>

    <div
      :if={not step2_valid?(assigns)}
      class="mt-4 rounded-[10px] border border-[#fdecec] bg-[#fff9f8] p-3"
    >
      <div class="text-[11.5px] font-semibold text-[#b42318]">
        Falta para continuar:
      </div>
      <ul class="mt-1 list-disc pl-4 text-[11.5px] text-[#b42318]">
        <li :for={msg <- step2_missing_reasons(assigns)}>{msg}</li>
      </ul>
    </div>

    <div class="mt-6 flex items-center justify-between">
      <button
        type="button"
        phx-click="goto"
        phx-value-step="upload"
        class="rounded-[8px] border border-[#e7e9ee] px-4 py-2.5 text-[13px] font-semibold text-[#344054] hover:border-[#d4d8df]"
      >
        ← Back
      </button>
      <button
        type="button"
        phx-click="goto"
        phx-value-step="review"
        disabled={not step2_valid?(assigns)}
        class="rounded-[8px] bg-[#CC5500] px-4 py-2.5 text-[13px] font-semibold text-white hover:bg-[#b34a00] disabled:cursor-not-allowed disabled:opacity-40"
      >
        Continue → Review
      </button>
    </div>
    """
  end

  # --- Step 3: Review ---

  defp review_step(assigns) do
    ~H"""
    <form phx-change="update_review" phx-submit="create">
      <label class="block text-[11px] font-semibold uppercase tracking-wide text-[#98a2b3]">
        Experiment name
      </label>
      <input
        type="text"
        name="experiment_name"
        value={@experiment_name}
        placeholder={default_name_placeholder(@saved_videos)}
        class="mt-2 w-full rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-2.5 text-[14px] text-[#0f1729] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none"
      />

      <div class="mt-5 overflow-hidden rounded-[13px] border border-[#e7e9ee] bg-white">
        <div class="grid grid-cols-[1.6fr_1fr_1fr_1fr] gap-3 border-b border-[#f4f5f7] px-4 py-2.5 text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
          <div>Vídeo</div>
          <div>Subject</div>
          <div>ROI</div>
          <div>Escala</div>
        </div>
        <div
          :for={v <- @saved_videos}
          class="grid grid-cols-[1.6fr_1fr_1fr_1fr] items-center gap-3 border-b border-[#f4f5f7] px-4 py-3 last:border-0"
        >
          <div class="truncate font-data text-[12.5px] text-[#0f1729]">{v.filename}</div>
          <input
            type="text"
            name={"subject[#{v.ref}]"}
            value={@specs[v.ref].subject_name}
            placeholder="Subject name"
            class="w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2 py-1.5 font-data text-[12.5px] text-[#0f1729] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none"
          />
          <div class="font-data text-[12px] text-[#667085]">
            {resolve_label(v.ref, @specs, :roi, @saved_videos) || "—"}
          </div>
          <div class="font-data text-[12px] text-[#667085]">
            {resolve_label(v.ref, @specs, :cal, @saved_videos) || "—"}
          </div>
        </div>
      </div>

      <div class="mt-6 flex items-center justify-between">
        <button
          type="button"
          phx-click="goto"
          phx-value-step="roi"
          class="rounded-[8px] border border-[#e7e9ee] px-4 py-2.5 text-[13px] font-semibold text-[#344054] hover:border-[#d4d8df]"
        >
          ← Back
        </button>
        <button
          type="submit"
          class="rounded-[8px] bg-[#CC5500] px-4 py-2.5 text-[13px] font-semibold text-white hover:bg-[#b34a00]"
        >
          Criar experimento ✓
        </button>
      </div>
    </form>
    """
  end

  # --- Presentational helpers ---

  attr :current, :string, required: true
  attr :mode, :string, required: true
  attr :label, :string, required: true

  defp mode_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="set_draw_mode"
      phx-value-mode={@mode}
      class={[
        "rounded-[6px] px-2.5 py-1.5 text-[11.5px] font-medium transition-colors",
        @current == @mode && "bg-[#CC5500] text-white",
        @current != @mode && "border border-[#e7e9ee] text-[#344054] hover:border-[#CC5500]"
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :kind, :string, required: true
  attr :resolved, :string, default: nil
  attr :event, :string, required: true
  attr :ref, :string, required: true

  defp inherit_control(assigns) do
    ~H"""
    <div class="rounded-[10px] border border-[#f4f5f7] bg-[#fafbfc] p-3">
      <div class="text-[12px] text-[#667085]">
        Referência de {@kind}:
        <span :if={@resolved} class="font-data font-medium text-[#0f1729]">{@resolved}</span>
        <span :if={!@resolved} class="font-medium text-[#b42318]">sem referência</span>
      </div>
      <button
        type="button"
        phx-click={@event}
        phx-value-ref={@ref}
        class="mt-2 inline-flex items-center gap-1 rounded-[6px] border border-[#e7e9ee] bg-white px-2.5 py-1.5 text-[12px] font-medium text-[#344054] hover:border-[#CC5500]"
      >
        <.icon name="hero-arrow-path-micro" class="size-3.5" /> Trocar referência
      </button>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :tag, :string, default: nil
  attr :optional, :boolean, default: false

  defp resource_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-[6px] px-2 py-0.5 font-data text-[10.5px]",
      @tag && "bg-[#f2f4f7] text-[#475467]",
      !@tag && @optional && "bg-[#f2f4f7] text-[#98a2b3]",
      !@tag && !@optional && "bg-[#fdecec] text-[#b42318]"
    ]}>
      {@label}: {@tag || "—"}
    </span>
    """
  end

  # --- Canvas shapes (drawn over the active video's frame) ---

  # Shows the shapes of whichever references the active video resolves to (its
  # own if it is a reference, or the inherited one), drawn on its own frame.
  defp canvas_shapes(assigns) do
    specs = assigns.specs
    active = assigns.active_ref
    cal_ref = resolve_ref(active, specs, :cal)
    roi_ref = resolve_ref(active, specs, :roi)
    cal = cal_ref && assigns.calibrations[cal_ref]

    %{
      valid_region: cal && cal.valid_region,
      scale: cal && cal.scale,
      scale2: cal && cal.scale2,
      rois: roi_ref |> then(&Map.get(assigns.rois, &1, [])) |> Enum.map(&shape_json/1)
    }
  end

  defp shape_json(%{shape: "circle", cx: cx, cy: cy, r: r}),
    do: %{shape: "circle", cx: cx, cy: cy, r: r}

  defp shape_json(%{shape: "polygon", points: points}),
    do: %{shape: "polygon", points: points}

  # --- Wizard state helpers ---

  defp default_spec(filename) do
    %{
      subject_name: Path.rootname(filename),
      roi_ref?: false,
      cal_ref?: false,
      roi_source: nil,
      cal_source: nil
    }
  end

  defp default_cal do
    %{
      valid_region: nil,
      scale: nil,
      scale_cm: "",
      scale2: nil,
      scale_cm2: "",
      threshold: "80",
      min_area: "250"
    }
  end

  defp toggle_ref(socket, ref, kind) do
    spec = socket.assigns.specs[ref]
    turning_on = not ref_flag(spec, kind)
    spec = put_ref_flag(spec, kind, turning_on)
    spec = if turning_on, do: put_source(spec, kind, nil), else: spec
    socket = assign(socket, :specs, Map.put(socket.assigns.specs, ref, spec))

    case kind do
      :cal when turning_on ->
        assign(
          socket,
          :calibrations,
          Map.put_new(socket.assigns.calibrations, ref, default_cal())
        )

      :cal ->
        assign(socket, :calibrations, Map.delete(socket.assigns.calibrations, ref))

      :roi when turning_on ->
        assign(socket, :rois, Map.put_new(socket.assigns.rois, ref, []))

      :roi ->
        assign(socket, :rois, Map.delete(socket.assigns.rois, ref))
    end
  end

  defp cycle_source(socket, ref, kind) do
    specs = socket.assigns.specs
    candidates = [nil | live_refs(socket.assigns, kind)]

    current =
      case source_of(specs[ref], kind) do
        {:inherit, r} -> r
        _ -> nil
      end

    idx = Enum.find_index(candidates, &(&1 == current)) || 0
    next = Enum.at(candidates, rem(idx + 1, length(candidates)))
    source = if is_nil(next), do: nil, else: {:inherit, next}

    assign(socket, :specs, Map.put(specs, ref, put_source(specs[ref], kind, source)))
  end

  defp ref_flag(%{roi_ref?: v}, :roi), do: v
  defp ref_flag(%{cal_ref?: v}, :cal), do: v
  defp put_ref_flag(spec, :roi, v), do: %{spec | roi_ref?: v}
  defp put_ref_flag(spec, :cal, v), do: %{spec | cal_ref?: v}
  defp source_of(%{roi_source: s}, :roi), do: s
  defp source_of(%{cal_source: s}, :cal), do: s
  defp put_source(spec, :roi, s), do: %{spec | roi_source: s}
  defp put_source(spec, :cal, s), do: %{spec | cal_source: s}

  defp live_refs(assigns, kind) do
    Enum.filter(entry_refs(assigns), fn r ->
      assigns.specs[r] && ref_flag(assigns.specs[r], kind)
    end)
  end

  defp entry_refs(assigns), do: Enum.map(assigns.saved_videos, & &1.ref)

  defp resolve_ref(ref, specs, kind) do
    spec = specs[ref]

    cond do
      is_nil(spec) -> nil
      ref_flag(spec, kind) -> ref
      match?({:inherit, _}, source_of(spec, kind)) -> resolve_inherit(spec, specs, kind)
      true -> nil
    end
  end

  defp resolve_inherit(spec, specs, kind) do
    {:inherit, r} = source_of(spec, kind)
    if specs[r] && ref_flag(specs[r], kind), do: r, else: nil
  end

  defp resolve_label(ref, specs, kind, videos) do
    case resolve_ref(ref, specs, kind) do
      nil -> nil
      ^ref -> "★ referência"
      other -> "herda de #{ref_filename(other, videos)}"
    end
  end

  defp ref_filename(ref, videos) do
    case Enum.find(videos, &(&1.ref == ref)) do
      nil -> ref
      v -> v.filename
    end
  end

  defp cal_field(calibrations, ref, key) do
    case Map.get(calibrations, ref) do
      nil -> nil
      cal -> Map.get(cal, key)
    end
  end

  defp scale_status(calibrations, ref) do
    case Map.get(calibrations, ref) do
      %{valid_region: vr, scale: s1, scale2: s2} = cal ->
        parts = [
          if(vr, do: "região ✓", else: "região —"),
          if(s1, do: "escala 1 ✓", else: "escala 1 —"),
          if(s2, do: "escala 2 ✓", else: "escala 2 —")
        ]

        px =
          case derive_px_per_10cm_pair(cal) do
            %{avg: avg, divergence_pct: pct} -> " · px_per_10cm=#{avg} (div #{pct}%)"
            nil -> ""
          end

        Enum.join(parts, " · ") <> px

      _ ->
        "região — · escala 1 — · escala 2 —"
    end
  end

  # --- Validation ---

  defp step1_valid?(assigns) do
    (assigns.saved_videos != [] or assigns.uploads.videos.entries != []) and
      Enum.all?(assigns.uploads.videos.entries, &(&1.progress == 100)) and
      upload_errors(assigns.uploads.videos) == []
  end

  defp step2_valid?(assigns) do
    refs = entry_refs(assigns)
    roi_refs = live_refs(assigns, :roi)
    roi_names = for r <- roi_refs, roi <- Map.get(assigns.rois, r, []), do: roi.name

    refs != [] and
      Enum.all?(refs, fn r ->
        case resolve_ref(r, assigns.specs, :cal) do
          nil -> false
          cal_ref -> cal_complete?(assigns.calibrations[cal_ref])
        end
      end) and
      Enum.all?(roi_refs, fn r ->
        Enum.all?(Map.get(assigns.rois, r, []), &present?(&1.name))
      end) and
      Enum.all?(roi_names, &present?/1) and
      length(roi_names) == length(Enum.uniq(roi_names))
  end

  # Human-readable breakdown of step2_valid?/1, shown next to the disabled
  # Continue button so an unmet condition (e.g. an unnamed ROI) is visible
  # instead of silently blocking navigation.
  defp step2_missing_reasons(assigns) do
    videos = assigns.saved_videos
    refs = entry_refs(assigns)
    roi_refs = live_refs(assigns, :roi)

    cal_msgs =
      for r <- refs,
          cal_ref = resolve_ref(r, assigns.specs, :cal),
          is_nil(cal_ref) or not cal_complete?(assigns.calibrations[cal_ref]) do
        "#{ref_filename(r, videos)}: escala/região válida incompleta"
      end

    roi_name_msgs =
      for r <- roi_refs,
          roi <- Map.get(assigns.rois, r, []),
          not present?(roi.name) do
        "#{ref_filename(r, videos)}: uma zona ROI está sem nome"
      end

    roi_names = for r <- roi_refs, roi <- Map.get(assigns.rois, r, []), do: roi.name

    dup_msgs =
      if length(roi_names) != length(Enum.uniq(roi_names)) do
        ["Duas zonas ROI têm o mesmo nome — nomes precisam ser únicos"]
      else
        []
      end

    (cal_msgs ++ roi_name_msgs ++ dup_msgs) |> Enum.uniq()
  end

  defp cal_complete?(nil), do: false

  defp cal_complete?(%{valid_region: vr, scale: s1, scale_cm: cm1, scale2: s2, scale_cm2: cm2}) do
    not is_nil(vr) and
      not is_nil(s1) and parse_float(cm1) > 0 and
      not is_nil(s2) and parse_float(cm2) > 0
  end

  defp present?(nil), do: false
  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: true

  defp parse_float(v) when is_number(v), do: v * 1.0

  defp parse_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp parse_float(_), do: 0.0

  # --- Misc ---

  defp experiment_name(name, saved_videos) do
    case String.trim(name || "") do
      "" ->
        saved_videos
        |> List.first()
        |> then(&((&1 && Path.rootname(&1.filename)) || "Untitled experiment"))

      n ->
        n
    end
  end

  defp default_name_placeholder(saved_videos) do
    case saved_videos do
      [first | _] -> Path.rootname(first.filename)
      _ -> "My experiment"
    end
  end

  defp static_dir, do: Path.join(:code.priv_dir(:mouse_tracker), "static")

  defp step_number(:upload), do: 1
  defp step_number(:roi), do: 2
  defp step_number(:review), do: 3

  defp step_title(:upload), do: "Upload videos"
  defp step_title(:roi), do: "ROI & scale"
  defp step_title(:review), do: "Review & create"

  defp ref_toggle_class(true),
    do:
      "inline-flex items-center gap-1 rounded-[7px] border border-[#CC5500] bg-[#fbeee4] px-2.5 py-1.5 text-[12px] font-semibold text-[#b34a00]"

  defp ref_toggle_class(false),
    do:
      "inline-flex items-center gap-1 rounded-[7px] border border-[#e7e9ee] bg-white px-2.5 py-1.5 text-[12px] font-medium text-[#344054] hover:border-[#CC5500]"

  defp upload_error_to_string(:too_large), do: "File is too large (max 4 GB)."
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 20)."
  defp upload_error_to_string(:not_accepted), do: "Unsupported type — use MP4, AVI or MOV."
  defp upload_error_to_string(_), do: "Upload error."
end
