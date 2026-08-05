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
  reference; other videos inherit from one, picked via a dropdown. Scale must
  resolve for every video (the pipeline needs a `valid_region` + `px_per_10cm`);
  ROIs are optional.
  """
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments
  alias MouseTracker.Experiments.Subjects
  alias MouseTracker.Tracking.FrameExtractor
  alias MouseTrackerWeb.ExperimentLive.New.Wizard

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    pipeline_defaults = %{
      threshold: to_string(user.default_threshold || 80),
      min_area: to_string(user.default_min_area || 250),
      peripheral_pct: to_string(user.default_peripheral_pct || 20),
      immobility_threshold_cm: to_string(user.default_immobility_threshold_cm || 2)
    }

    {:ok,
     socket
     |> assign(:page_title, "New experiment")
     |> assign(:step, :upload)
     |> assign(:upload_token, Ecto.UUID.generate())
     |> assign(:saved_videos, [])
     |> assign(:specs, %{})
     |> assign(:calibrations, %{})
     |> assign(:rois, %{})
     |> assign(:active_ref, nil)
     |> assign(:draw_mode, "roi_polygon")
     |> assign(:experiment_name, "")
     |> assign(:pipeline_defaults, pipeline_defaults)
     |> assign(:existing_subjects, Subjects.list_subjects(socket.assigns.current_scope))
     |> allow_upload(:videos, upload_opts())}
  end

  defp upload_opts do
    [
      accept: ~w(.mp4 .avi .mov),
      max_entries: 20,
      max_file_size: 4_000_000_000,
      auto_upload: true
    ]
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    step = socket.assigns.live_action
    socket = assign(socket, :step, step)

    socket =
      cond do
        step in [:roi, :review] and socket.assigns.saved_videos == [] ->
          push_patch(socket, to: ~p"/experiments/new")

        step == :review and not Wizard.step2_valid?(socket.assigns) ->
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

  def handle_event("set_reference_frame", %{"ref" => ref, "frame" => frame}, socket) do
    {:noreply, set_reference_frame(socket, ref, frame)}
  end

  def handle_event("toggle_cal_ref", %{"ref" => ref}, socket) do
    {:noreply, toggle_ref(socket, ref, :cal)}
  end

  def handle_event("toggle_roi_ref", %{"ref" => ref}, socket) do
    {:noreply, toggle_ref(socket, ref, :roi)}
  end

  def handle_event("set_cal_source", %{"ref" => ref, "source" => value}, socket) do
    {:noreply, set_source(socket, ref, :cal, value)}
  end

  def handle_event("set_roi_source", %{"ref" => ref, "source" => value}, socket) do
    {:noreply, set_source(socket, ref, :roi, value)}
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

  def handle_event(
        "cal_setting",
        %{
          "threshold" => th,
          "min_area" => ma,
          "peripheral_pct" => pp,
          "immobility_threshold_cm" => it
        },
        socket
      ) do
    {:noreply,
     update_calibration(
       socket,
       socket.assigns.active_ref,
       &%{&1 | threshold: th, min_area: ma, peripheral_pct: pp, immobility_threshold_cm: it}
     )}
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
    subject_sel = params["subject"] || %{}
    subject_new_names = params["subject_new_name"] || %{}

    specs =
      Enum.reduce(subject_sel, socket.assigns.specs, fn {ref, value}, acc ->
        case acc do
          %{^ref => spec} ->
            ref_value = Wizard.parse_subject_ref(value, Map.get(subject_new_names, ref, ""))
            Map.put(acc, ref, %{spec | subject_ref: ref_value})

          _ ->
            acc
        end
      end)

    {:noreply,
     socket
     |> assign(:specs, specs)
     |> assign(:experiment_name, params["experiment_name"] || socket.assigns.experiment_name)}
  end

  def handle_event("create", _params, socket) do
    if Wizard.step2_valid?(socket.assigns) do
      do_create(socket)
    else
      {:noreply, put_flash(socket, :error, "Complete ROI & scale first.")}
    end
  end

  # --- Saving uploads + frame extraction ---

  defp save_pending_uploads(socket) do
    token = socket.assigns.upload_token

    # Copying the upload to disk must happen inside consume_uploaded_entries
    # (the tmp path is only valid during the callback), but frame extraction
    # shells out to a fresh Python interpreter per video (~seconds of startup
    # each) and doesn't need the tmp path, so it runs afterwards, in parallel.
    copied =
      consume_uploaded_entries(socket, :videos, fn %{path: tmp}, entry ->
        video_dir = Path.join([static_dir(), "uploads", "videos", token])
        File.mkdir_p!(video_dir)

        filepath = Path.join(video_dir, "#{entry.ref}-#{entry.client_name}")
        File.cp!(tmp, filepath)

        {:ok,
         %{
           ref: entry.ref,
           filename: entry.client_name,
           filepath: filepath,
           file_size_bytes: File.stat!(filepath).size
         }}
      end)

    frame_dir = Path.join([static_dir(), "uploads", "frames", token])

    consumed =
      copied
      |> Task.async_stream(
        fn v ->
          frame_path = Path.join(frame_dir, "#{v.ref}.png")

          {frame_url, meta} =
            case FrameExtractor.extract_first_frame(v.filepath, frame_path) do
              {:ok, info} -> {"/uploads/frames/#{token}/#{v.ref}.png", info}
              {:error, _} -> {nil, %{}}
            end

          v
          |> Map.put(:frame_url, frame_url)
          |> Map.merge(meta)
        end,
        max_concurrency: System.schedulers_online(),
        timeout: :timer.seconds(30),
        on_timeout: :kill_task
      )
      |> Enum.zip(copied)
      |> Enum.map(fn
        {{:ok, v}, _original} -> v
        {{:exit, _reason}, original} -> Map.put(original, :frame_url, nil)
      end)

    saved = socket.assigns.saved_videos ++ consumed

    specs =
      Enum.reduce(consumed, socket.assigns.specs, fn v, acc ->
        Map.put_new(acc, v.ref, Wizard.default_spec(v.filename))
      end)

    active = socket.assigns.active_ref || saved |> List.first() |> then(&(&1 && &1.ref))

    socket
    |> assign(:saved_videos, saved)
    |> assign(:specs, specs)
    |> assign(:active_ref, active)
  end

  # Re-extracts the reference frame (used as the tracking background model and
  # the heatmap underlay) for one video and stores its index. Lets the user pick
  # a clean frame when the first one is contaminated (e.g. a hand still in the
  # arena). ROI/scale geometry is in native pixels, so it stays valid — only the
  # displayed frame image changes; the RoiCanvas hook reloads it on src change.
  defp set_reference_frame(socket, ref, frame_str) do
    video = Enum.find(socket.assigns.saved_videos, &(&1.ref == ref))

    with %{filepath: filepath} <- video,
         {n, _} <- Integer.parse(to_string(frame_str)) do
      n = Wizard.clamp_frame(n, video)
      token = socket.assigns.upload_token
      frame_path = Path.join([static_dir(), "uploads", "frames", token, "#{ref}-#{n}.png"])

      case FrameExtractor.extract_first_frame(filepath, frame_path, n) do
        {:ok, _meta} ->
          url = "/uploads/frames/#{token}/#{ref}-#{n}.png"

          update_saved_video(socket, ref, fn v ->
            v |> Map.put(:frame_url, url) |> Map.put(:background_frame, n)
          end)

        {:error, _} ->
          put_flash(socket, :error, "Could not extract frame #{n} from this video.")
      end
    else
      _ -> socket
    end
  end

  defp update_saved_video(socket, ref, fun) do
    saved = Enum.map(socket.assigns.saved_videos, &if(&1.ref == ref, do: fun.(&1), else: &1))
    assign(socket, :saved_videos, saved)
  end

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
    spec && Wizard.ref_flag(spec, kind)
  end

  defp update_calibration(socket, ref, fun) do
    default = Wizard.default_cal(socket.assigns.pipeline_defaults)
    cal = fun.(Map.get(socket.assigns.calibrations, ref, default))
    assign(socket, :calibrations, Map.put(socket.assigns.calibrations, ref, cal))
  end

  # --- Create ---

  defp do_create(socket) do
    specs = socket.assigns.specs

    payload = %{
      name: Wizard.experiment_name(socket.assigns.experiment_name, socket.assigns.saved_videos),
      calibrations: Wizard.build_calibrations(socket.assigns),
      rois: Wizard.build_rois(socket.assigns),
      videos:
        Enum.map(socket.assigns.saved_videos, fn v ->
          %{
            filename: v.filename,
            filepath: v.filepath,
            background_frame: Map.get(v, :background_frame, 0),
            file_size_bytes: Map.get(v, :file_size_bytes),
            fps: Map.get(v, :fps),
            duration_seconds: Map.get(v, :duration_seconds),
            frame_count: Map.get(v, :frame_count),
            width: Map.get(v, :width),
            height: Map.get(v, :height),
            subject_ref: specs[v.ref].subject_ref,
            cal_ref: Wizard.resolve_ref(v.ref, specs, :cal),
            roi_ref: Wizard.resolve_ref(v.ref, specs, :roi)
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
    <form phx-change="validate_upload" phx-submit="validate_upload">
      <label
        phx-drop-target={@uploads.videos.ref}
        class="flex cursor-pointer flex-col items-center justify-center rounded-[13px] border-2 border-dashed border-[#cdd2da] bg-white px-6 py-12 text-center transition-colors hover:border-[#CC5500] hover:bg-[#fdf6f0]"
      >
        <div class="flex size-11 items-center justify-center rounded-full bg-[#fbeee4] text-[#CC5500]">
          <.icon name="hero-arrow-up-tray" class="size-5" />
        </div>

        <div class="mt-3 text-[13.5px] text-[#344054]">
          Drag videos here, or <span class="font-semibold text-[#CC5500]">browse</span>
        </div>

        <div class="mt-1 font-data text-[11.5px] text-[#98a2b3]">
          MP4 · AVI · MOV — up to 4 GB — 30–60 fps
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
      <.button variant="secondary" navigate={~p"/experiments"}>
        Cancel
      </.button>

      <div class="flex flex-col items-end gap-1">
        <.button
          type="button"
          phx-click="goto"
          phx-value-step="roi"
          disabled={not Wizard.step1_valid?(assigns)}
        >
          Continue → ROI & scale
        </.button>
        <span class="text-[11px] text-[#98a2b3]">This may take a while — extracting a frame from each video.</span>
      </div>
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
          assigns.calibrations[active] &&
            Wizard.derive_px_per_10cm_pair(assigns.calibrations[active]),
        shapes_json: Jason.encode!(canvas_shapes(assigns))
      )

    ~H"""
    <div class="grid grid-cols-1 gap-5 lg:grid-cols-[1.5fr_1fr]">
      <.canvas_section
        active_video={@active_video}
        active_ref={@active_ref}
        active_spec={@active_spec}
        draw_mode={@draw_mode}
        shapes_json={@shapes_json}
      />

      <div class="space-y-4">
        <.scale_card
          :if={@active_spec}
          active_spec={@active_spec}
          active_ref={@active_ref}
          draw_mode={@draw_mode}
          calibrations={@calibrations}
          scale_summary={@scale_summary}
          specs={@specs}
          saved_videos={@saved_videos}
        />

        <.roi_card
          :if={@active_spec}
          active_spec={@active_spec}
          active_ref={@active_ref}
          draw_mode={@draw_mode}
          active_rois={@active_rois}
          specs={@specs}
          saved_videos={@saved_videos}
        />

        <.batch_list saved_videos={@saved_videos} active_ref={@active_ref} specs={@specs} />
      </div>
    </div>

    <div
      :if={not Wizard.step2_valid?(assigns)}
      class="mt-4 rounded-[10px] border border-[#fdecec] bg-[#fff9f8] p-3"
    >
      <div class="text-[11.5px] font-semibold text-[#b42318]">
        Missing to continue:
      </div>

      <ul class="mt-1 list-disc pl-4 text-[11.5px] text-[#b42318]">
        <li :for={msg <- Wizard.step2_missing_reasons(assigns)}>{msg}</li>
      </ul>
    </div>

    <div class="mt-6 flex items-center justify-between">
      <.button type="button" variant="secondary" phx-click="goto" phx-value-step="upload">
        ← Back
      </.button>

      <.button
        type="button"
        phx-click="goto"
        phx-value-step="review"
        disabled={not Wizard.step2_valid?(assigns)}
      >
        Continue → Review
      </.button>
    </div>
    """
  end

  # --- Step 2 cards ---

  attr :active_video, :map, default: nil
  attr :active_ref, :string, required: true
  attr :active_spec, :map, default: nil
  attr :draw_mode, :string, required: true
  attr :shapes_json, :string, required: true

  # The frame/canvas the user draws on, plus the reference-frame picker and
  # the "use as scale/ROI reference" toggles — everything tied to *which*
  # video is currently active, as opposed to the scale/ROI data itself.
  defp canvas_section(assigns) do
    ~H"""
    <div>
      <div
        :if={@active_video && @active_video.frame_url}
        id="roi-canvas"
        phx-hook="RoiCanvas"
        data-frame={@active_video.frame_url}
        data-mode={@draw_mode}
        data-shapes={@shapes_json}
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

      <.reference_frame_form
        :if={@active_video && @active_video.frame_url}
        active_ref={@active_ref}
        active_video={@active_video}
      />

      <div :if={@active_spec} class="mt-3 flex flex-wrap gap-2">
        <button
          type="button"
          phx-click="toggle_cal_ref"
          phx-value-ref={@active_ref}
          class={ref_toggle_class(@active_spec.cal_ref?)}
        >
          <.icon name="hero-star-micro" class="size-4" /> {if @active_spec.cal_ref?,
            do: "★ scale reference",
            else: "use as scale reference"}
        </button>

        <button
          type="button"
          phx-click="toggle_roi_ref"
          phx-value-ref={@active_ref}
          class={ref_toggle_class(@active_spec.roi_ref?)}
        >
          <.icon name="hero-star-micro" class="size-4" /> {if @active_spec.roi_ref?,
            do: "★ ROI reference",
            else: "use as ROI reference"}
        </button>
      </div>
    </div>
    """
  end

  attr :active_ref, :string, required: true
  attr :active_video, :map, required: true

  defp reference_frame_form(assigns) do
    ~H"""
    <div class="mt-3">
      <form
        id={"ref-frame-#{@active_ref}"}
        phx-submit="set_reference_frame"
        class="flex flex-wrap items-end gap-2"
      >
        <input type="hidden" name="ref" value={@active_ref} />
        <label class="block">
          <span class="text-[11px] text-[#667085]">Reference frame (background)</span>
          <input
            type="number"
            name="frame"
            min="0"
            value={Map.get(@active_video, :background_frame, 0)}
            class="mt-1 w-28 rounded-[6px] border border-[#e7e9ee] bg-white px-2.5 py-1.5 font-data text-[12.5px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
          />
        </label>

        <button
          type="submit"
          class="rounded-[6px] border border-[#e7e9ee] px-3 py-1.5 text-[12px] font-semibold text-[#344054] hover:border-[#d4d8df]"
        >
          Load frame
        </button>

        <span
          :if={Map.get(@active_video, :frame_count)}
          class="pb-1.5 font-data text-[11px] text-[#98a2b3]"
        >
          of {@active_video.frame_count} frames
        </span>
      </form>

      <p class="mt-1 text-[11px] text-[#8a93a3]">
        Switch the frame if the first one has a hand or obstruction in the arena — it's used as the background for detection and the heatmap.
      </p>
    </div>
    """
  end

  attr :active_spec, :map, required: true
  attr :active_ref, :string, required: true
  attr :draw_mode, :string, required: true
  attr :calibrations, :map, required: true
  attr :scale_summary, :map, default: nil
  attr :specs, :map, required: true
  attr :saved_videos, :list, required: true

  # Either the scale/valid-region editor (if this video is the scale
  # reference) or an `inherit_control` pointing at whichever video it inherits
  # scale from.
  defp scale_card(assigns) do
    ~H"""
    <div :if={@active_spec.cal_ref?} class="rounded-[13px] border border-[#e7e9ee] bg-white p-[16px]">
      <div class="text-[12px] font-bold text-[#0f1729]">Scale & valid region</div>

      <div class="mt-2 flex flex-wrap gap-1.5">
        <.mode_button current={@draw_mode} mode="valid_region" label="Valid region" />
        <.mode_button current={@draw_mode} mode="scale" label="Scale 1 (2 pts)" />
        <.mode_button current={@draw_mode} mode="scale2" label="Scale 2 (2 pts)" />
      </div>

      <form
        id={"scale-cm-#{@active_ref}"}
        phx-change="set_scale_cm"
        phx-submit="set_scale_cm"
        class="mt-3"
      >
        <label class="text-[11px] text-[#667085]">Real-world measure of reference 1 (cm)</label>
        <input
          type="number"
          step="any"
          name="value"
          value={Wizard.cal_field(@calibrations, @active_ref, :scale_cm)}
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
        <label class="text-[11px] text-[#667085]">Real-world measure of reference 2 (cm)</label>
        <input
          type="number"
          step="any"
          name="value"
          value={Wizard.cal_field(@calibrations, @active_ref, :scale_cm2)}
          placeholder="ex: 40"
          class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2.5 py-1.5 font-data text-[12.5px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
        />
      </form>

      <div class="mt-2 font-data text-[11px] text-[#8a93a3]">
        {Wizard.scale_status(@calibrations, @active_ref)}
      </div>

      <div
        :if={@scale_summary && @scale_summary.divergence_pct > Wizard.divergence_warning_pct()}
        class="mt-2 rounded-[8px] border border-[#fde68a] bg-[#fffbeb] p-2.5"
      >
        <div class="text-[11.5px] font-semibold text-[#92400e]">
          The two scale measurements diverge by {@scale_summary.divergence_pct}% (expected ≤{Wizard.divergence_warning_pct()}%). Double-check the points clicked on each segment.
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
            value={Wizard.cal_field(@calibrations, @active_ref, :threshold)}
            class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2 py-1.5 font-data text-[12px] focus:border-[#CC5500] focus:outline-none"
          />
        </label>

        <label class="block">
          <span class="text-[11px] text-[#667085]">Min area</span>
          <input
            type="number"
            name="min_area"
            value={Wizard.cal_field(@calibrations, @active_ref, :min_area)}
            class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2 py-1.5 font-data text-[12px] focus:border-[#CC5500] focus:outline-none"
          />
        </label>

        <label class="block">
          <span class="text-[11px] text-[#667085]">Peripheral %</span>
          <input
            type="number"
            step="0.1"
            name="peripheral_pct"
            value={Wizard.cal_field(@calibrations, @active_ref, :peripheral_pct)}
            class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2 py-1.5 font-data text-[12px] focus:border-[#CC5500] focus:outline-none"
          />
        </label>

        <label class="block">
          <span class="text-[11px] text-[#667085]">Immobility threshold (cm/s)</span>
          <input
            type="number"
            step="0.1"
            name="immobility_threshold_cm"
            value={Wizard.cal_field(@calibrations, @active_ref, :immobility_threshold_cm)}
            class="mt-1 w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2 py-1.5 font-data text-[12px] focus:border-[#CC5500] focus:outline-none"
          />
        </label>
      </form>
    </div>

    <.inherit_control
      :if={not @active_spec.cal_ref?}
      kind="scale"
      resolved={Wizard.resolve_label(@active_ref, @specs, :cal, @saved_videos)}
      event="set_cal_source"
      ref={@active_ref}
      options={Wizard.source_options(%{specs: @specs, saved_videos: @saved_videos}, :cal)}
      selected={Wizard.current_source_ref(@specs[@active_ref], :cal)}
    />
    """
  end

  attr :active_spec, :map, required: true
  attr :active_ref, :string, required: true
  attr :draw_mode, :string, required: true
  attr :active_rois, :list, required: true
  attr :specs, :map, required: true
  attr :saved_videos, :list, required: true

  # Either the ROI list editor (if this video is the ROI reference) or an
  # `inherit_control` pointing at whichever video it inherits ROIs from.
  defp roi_card(assigns) do
    ~H"""
    <div :if={@active_spec.roi_ref?} class="rounded-[13px] border border-[#e7e9ee] bg-white p-[16px]">
      <div class="text-[12px] font-bold text-[#0f1729]">ROIs (zones)</div>

      <div class="mt-2 flex flex-wrap gap-1.5">
        <.mode_button current={@draw_mode} mode="roi_polygon" label="Polygon (4 pts)" />
        <.mode_button current={@draw_mode} mode="roi_circle" label="Circle" />
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
        Choose a mode above and draw on the frame to add zones.
      </div>
    </div>

    <.inherit_control
      :if={not @active_spec.roi_ref?}
      kind="ROI"
      resolved={Wizard.resolve_label(@active_ref, @specs, :roi, @saved_videos)}
      event="set_roi_source"
      ref={@active_ref}
      options={Wizard.source_options(%{specs: @specs, saved_videos: @saved_videos}, :roi)}
      selected={Wizard.current_source_ref(@specs[@active_ref], :roi)}
    />
    """
  end

  attr :saved_videos, :list, required: true
  attr :active_ref, :string, required: true
  attr :specs, :map, required: true

  defp batch_list(assigns) do
    ~H"""
    <div>
      <div class="text-[11px] font-semibold uppercase tracking-wide text-[#98a2b3]">
        Videos in this batch
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
              label="Scale"
              tag={Wizard.resolve_label(v.ref, @specs, :cal, @saved_videos)}
            />
            <.resource_badge
              label="ROI"
              tag={Wizard.resolve_label(v.ref, @specs, :roi, @saved_videos)}
              optional
            />
          </div>
        </li>
      </ul>
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
        placeholder={Wizard.default_name_placeholder(@saved_videos)}
        class="mt-2 w-full rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-2.5 text-[14px] text-[#0f1729] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none"
      />
      <div class="mt-5 overflow-hidden rounded-[13px] border border-[#e7e9ee] bg-white">
        <div class="grid grid-cols-[1.6fr_1fr_1fr_1fr] gap-3 border-b border-[#f4f5f7] px-4 py-2.5 text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
          <div>Video</div>

          <div>Subject</div>

          <div>ROI</div>

          <div>Scale</div>
        </div>

        <div
          :for={v <- @saved_videos}
          class="grid grid-cols-[1.6fr_1fr_1fr_1fr] items-center gap-3 border-b border-[#f4f5f7] px-4 py-3 last:border-0"
        >
          <div class="truncate font-data text-[12.5px] text-[#0f1729]">{v.filename}</div>

          <div class="space-y-1.5">
            <select
              name={"subject[#{v.ref}]"}
              class="w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2 py-1.5 font-data text-[12.5px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
            >
              <option value="" selected={@specs[v.ref].subject_ref == nil}>— No subject —</option>

              <option
                :for={s <- @existing_subjects}
                value={s.id}
                selected={@specs[v.ref].subject_ref == {:existing, s.id}}
              >
                {s.name}
              </option>

              <option value="new" selected={match?({:new, _}, @specs[v.ref].subject_ref)}>
                + New subject
              </option>
            </select>

            <input
              :if={match?({:new, _}, @specs[v.ref].subject_ref)}
              type="text"
              name={"subject_new_name[#{v.ref}]"}
              value={Wizard.subject_new_name(@specs[v.ref].subject_ref)}
              placeholder="New subject name"
              class="w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2 py-1.5 font-data text-[12.5px] text-[#0f1729] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none"
            />
          </div>

          <div class="font-data text-[12px] text-[#667085]">
            {Wizard.resolve_label(v.ref, @specs, :roi, @saved_videos) || "—"}
          </div>

          <div class="font-data text-[12px] text-[#667085]">
            {Wizard.resolve_label(v.ref, @specs, :cal, @saved_videos) || "—"}
          </div>
        </div>
      </div>

      <div class="mt-6 flex items-center justify-between">
        <.button type="button" variant="secondary" phx-click="goto" phx-value-step="roi">
          ← Back
        </.button>

        <.button type="submit">
          Create experiment ✓
        </.button>
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
  attr :options, :list, required: true
  attr :selected, :string, default: nil

  defp inherit_control(assigns) do
    ~H"""
    <div class="rounded-[10px] border border-[#f4f5f7] bg-[#fafbfc] p-3">
      <div class="text-[12px] text-[#667085]">
        {@kind} reference:
        <span :if={@resolved} class="font-data font-medium text-[#0f1729]">{@resolved}</span>
        <span :if={!@resolved} class="font-medium text-[#b42318]">no reference</span>
      </div>

      <form id={"inherit-#{@event}-#{@ref}"} phx-change={@event} class="mt-2">
        <input type="hidden" name="ref" value={@ref} />
        <select
          name="source"
          class="w-full rounded-[6px] border border-[#e7e9ee] bg-white px-2.5 py-1.5 font-data text-[12px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
        >
          <option value="" selected={@selected == nil}>— no reference —</option>

          <option :for={opt <- @options} value={opt.ref} selected={@selected == opt.ref}>
            {opt.filename}
          </option>
        </select>
      </form>
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
    cal_ref = Wizard.resolve_ref(active, specs, :cal)
    roi_ref = Wizard.resolve_ref(active, specs, :roi)
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

  # --- Wizard state mutation (delegates flag/resolution logic to Wizard) ---

  defp toggle_ref(socket, ref, kind) do
    spec = socket.assigns.specs[ref]
    turning_on = not Wizard.ref_flag(spec, kind)
    spec = Wizard.put_ref_flag(spec, kind, turning_on)
    spec = if turning_on, do: Wizard.put_source(spec, kind, nil), else: spec
    socket = assign(socket, :specs, Map.put(socket.assigns.specs, ref, spec))

    case kind do
      :cal when turning_on ->
        assign(
          socket,
          :calibrations,
          Map.put_new(
            socket.assigns.calibrations,
            ref,
            Wizard.default_cal(socket.assigns.pipeline_defaults)
          )
        )

      :cal ->
        assign(socket, :calibrations, Map.delete(socket.assigns.calibrations, ref))

      :roi when turning_on ->
        assign(socket, :rois, Map.put_new(socket.assigns.rois, ref, []))

      :roi ->
        assign(socket, :rois, Map.delete(socket.assigns.rois, ref))
    end
  end

  defp set_source(socket, ref, kind, value) do
    specs = socket.assigns.specs
    source = if value in [nil, ""], do: nil, else: {:inherit, value}
    assign(socket, :specs, Map.put(specs, ref, Wizard.put_source(specs[ref], kind, source)))
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
