defmodule MouseTrackerWeb.ExperimentLive.RoiEdit do
  @moduledoc """
  Lets the user go back and adjust a ROI's geometry (or just its name) after
  it's already been created via the upload wizard. Reached from a video's
  attached-ROI chip on `ExperimentLive.Show`, so the canvas always uses that
  video's own frame as background.

  Reuses the `RoiCanvas` JS hook exactly as the wizard does: the ROI can't be
  dragged in place (the hook has no vertex-editing support), so its current
  geometry is shown as a read-only reference overlay and drawing a new shape
  on top replaces it. If the ROI is attached to any `"done"`/`"processing"`
  video (see `Experiments.roi_locked?/1`), geometry edits are blocked — only
  the name stays editable — and a "Duplicate" action offers an independent,
  freely-editable copy instead (editing a shared ROI's geometry in place
  would desync it from what already-produced results were measured against).
  """
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments
  alias MouseTracker.Experiments.Rois
  alias MouseTracker.Tracking.FrameExtractor

  @impl true
  def mount(%{"video_id" => video_id, "roi_id" => roi_id}, _session, socket) do
    video = Experiments.get_video_with_experiment!(video_id)

    if video.experiment.user_id != socket.assigns.current_scope.user.id do
      raise Ecto.NoResultsError, queryable: MouseTracker.Experiments.Video
    end

    roi = Rois.get_roi!(socket.assigns.current_scope, roi_id)

    unless roi in Rois.list_rois_for_video(video) do
      raise Ecto.NoResultsError, queryable: MouseTracker.Experiments.Roi
    end

    {:ok,
     socket
     |> assign(:page_title, "Edit ROI")
     |> assign(:video, video)
     |> assign(:roi, roi)
     |> assign(:locked?, Rois.roi_locked?(roi))
     |> assign(:name, roi.name)
     |> assign(:draw_mode, roi_draw_mode(roi))
     |> assign(:new_geometry, nil)
     |> assign_frame(video)}
  end

  defp roi_draw_mode(%{shape: "circle"}), do: "roi_circle"
  defp roi_draw_mode(_), do: "roi_polygon"

  defp assign_frame(socket, video) do
    assign_async(socket, :frame_url, fn ->
      {:ok, %{frame_url: FrameExtractor.ensure_cached_frame(video)}}
    end)
  end

  # --- Events ---

  @impl true
  def handle_event("update_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :name, name)}
  end

  def handle_event("shape_drawn", shape, socket) do
    if socket.assigns.locked? do
      {:noreply, socket}
    else
      {:noreply, apply_shape(socket, shape)}
    end
  end

  def handle_event("save", params, socket) do
    name = Map.get(params, "value", socket.assigns.name)
    attrs = Map.put(geometry_attrs(socket.assigns.new_geometry), :name, name)

    case Rois.update_roi(socket.assigns.current_scope, socket.assigns.roi, attrs) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "ROI updated.")
         |> push_navigate(to: ~p"/experiments/#{socket.assigns.video.experiment_id}")}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not save — check the name is not already taken.")}
    end
  end

  def handle_event("duplicate", _params, socket) do
    case Rois.duplicate_roi(socket.assigns.current_scope, socket.assigns.roi) do
      {:ok, new_roi} ->
        {:noreply,
         socket
         |> put_flash(:info, "Duplicated as \"#{new_roi.name}\" — now editable.")
         |> push_navigate(to: ~p"/videos/#{socket.assigns.video.id}/rois/#{new_roi.id}/edit")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not duplicate this ROI.")}
    end
  end

  defp apply_shape(socket, %{"kind" => "roi_polygon", "points" => points}) do
    assign(socket, :new_geometry, %{shape: "polygon", points: points})
  end

  defp apply_shape(socket, %{"kind" => "roi_circle", "cx" => cx, "cy" => cy, "r" => r}) do
    assign(socket, :new_geometry, %{shape: "circle", cx: cx, cy: cy, r: r})
  end

  defp apply_shape(socket, _shape), do: socket

  defp geometry_attrs(nil), do: %{}

  defp geometry_attrs(%{shape: "circle", cx: cx, cy: cy, r: r}),
    do: %{shape: "circle", x: cx, y: cy, radius: r}

  defp geometry_attrs(%{shape: "polygon", points: [x0, y0, x1, y1, x2, y2, x3, y3]}) do
    %{
      shape: "polygon",
      x: x0,
      y: y0,
      x1: x0,
      y1: y0,
      x2: x1,
      y2: y1,
      x3: x2,
      y3: y2,
      x4: x3,
      y4: y3
    }
  end

  # --- Canvas shapes (the ROI's current geometry, shown as a read-only ghost) ---

  defp canvas_shapes(%{shape: "circle"} = roi),
    do: %{rois: [%{shape: "circle", cx: roi.x, cy: roi.y, r: roi.radius}]}

  defp canvas_shapes(%{shape: "polygon"} = roi) do
    %{
      rois: [
        %{
          shape: "polygon",
          points: [roi.x1, roi.y1, roi.x2, roi.y2, roi.x3, roi.y3, roi.x4, roi.y4]
        }
      ]
    }
  end

  defp canvas_shapes(roi), do: %{rois: [%{shape: "polygon", points: rectangle_as_polygon(roi)}]}

  defp rectangle_as_polygon(%{x: x, y: y, w: w, h: h}),
    do: [x, y, x + w, y, x + w, y + h, x, y + h]

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={:experiments}
      breadcrumb={@video.experiment.name}
      page_title="Edit ROI"
    >
      <div class="mx-auto max-w-[900px]">
        <.link
          navigate={~p"/experiments/#{@video.experiment_id}"}
          class="inline-flex items-center gap-1 text-[12.5px] text-[#667085] hover:text-[#0f1729]"
        >
          <.icon name="hero-chevron-left-micro" class="size-4" /> {@video.experiment.name}
        </.link>

        <h1 class="mt-3 text-[23px] font-bold text-[#0f1729]">Edit ROI</h1>

        <p class="mt-1 font-data text-[12.5px] text-[#8a93a3]">{@video.filename}</p>

        <div
          :if={@locked?}
          class="mt-4 rounded-[10px] border border-[#fde68a] bg-[#fffbeb] p-3.5"
        >
          <div class="text-[12.5px] font-semibold text-[#92400e]">
            Geometry is locked — a processed video uses this ROI
          </div>

          <p class="mt-1 text-[11.5px] text-[#92400e]">
            This ROI is attached to at least one video that is already done or currently
            processing. Editing its shape now would desync it from those results, so only
            the name can be changed here. Duplicate it to get an independent, freely
            editable copy.
          </p>

          <button
            type="button"
            phx-click="duplicate"
            class="mt-2.5 inline-flex items-center gap-1.5 rounded-[8px] bg-[#92400e] px-3 py-1.5 text-[12px] font-semibold text-white hover:bg-[#78350f]"
          >
            <.icon name="hero-document-duplicate-micro" class="size-4" /> Duplicate ROI
          </button>
        </div>

        <form id="roi-edit-form" phx-change="update_name" phx-submit="save" class="mt-5">
          <label class="block text-[11px] font-semibold uppercase tracking-wide text-[#98a2b3]">
            Name
          </label>

          <input
            type="text"
            name="value"
            value={@name}
            class="mt-2 w-full max-w-sm rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-2 text-[14px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
          />
          <div :if={!@locked?} class="mt-5">
            <div class="text-[12px] font-bold text-[#0f1729]">Geometry</div>

            <p class="mt-1 text-[11.5px] text-[#98a2b3]">
              The current shape is shown as a reference. Draw a new one on top to replace
              it, or leave it untouched to keep the existing geometry.
            </p>

            <.async_result :let={frame_url} assign={@frame_url}>
              <:loading>
                <div class="mt-2 flex h-64 items-center justify-center rounded-[10px] border border-dashed border-[#d4d8df] text-center font-data text-[12px] text-[#98a2b3]">
                  Extracting frame…
                </div>
              </:loading>

              <:failed>
                <div class="mt-2 flex h-64 items-center justify-center rounded-[10px] border border-dashed border-[#d4d8df] text-center font-data text-[12px] text-[#98a2b3]">
                  Could not extract a frame from this video.
                </div>
              </:failed>

              <div :if={frame_url} class="mt-2">
                <div
                  id="roi-edit-canvas"
                  phx-hook="RoiCanvas"
                  data-frame={frame_url}
                  data-mode={@draw_mode}
                  data-shapes={Jason.encode!(canvas_shapes(@roi))}
                  class="relative overflow-hidden rounded-[10px] border border-[#e7e9ee] bg-[#11161f]"
                >
                  <img data-role="frame" src={frame_url} class="block w-full select-none" />
                  <canvas data-role="overlay" class="absolute inset-0 h-full w-full cursor-crosshair"></canvas>
                </div>
              </div>

              <div
                :if={!frame_url}
                class="mt-2 flex h-64 items-center justify-center rounded-[10px] border border-dashed border-[#d4d8df] text-center font-data text-[12px] text-[#98a2b3]"
              >
                Could not extract a frame from this video.
              </div>
            </.async_result>
          </div>

          <div class="mt-6 flex items-center justify-between">
            <.button variant="secondary" navigate={~p"/experiments/#{@video.experiment_id}"}>
              Cancel
            </.button>

            <.button type="submit">
              Save
            </.button>
          </div>
        </form>
      </div>
    </Layouts.locomo>
    """
  end
end
