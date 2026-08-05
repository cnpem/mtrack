defmodule MouseTrackerWeb.DatasetLive.Index do
  @moduledoc """
  Datasets library (`/datasets`): every video the user has uploaded, across all
  experiments, with metadata (duration, fps, size, subject, calibration,
  status) and a metrics preview for tracked videos. Two views toggle between a
  per-video table and a per-subject aggregate (reusing
  `Experiments.subject_metric_aggregate/1`).

  True cross-experiment *reuse* of a video (attaching an already-uploaded video
  to a new experiment) needs a schema change (Video is `belongs_to :experiment`
  today) and is a later phase — this screen is the read-only library.
  """
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments.Reporting
  alias MouseTrackerWeb.VideoStatusSync

  @tabs [{"all", "All"}, {"done", "Done"}, {"processing", "Processing"}, {"pending", "Pending"}]

  @impl true
  def mount(_params, _session, socket) do
    videos = Reporting.list_all_videos(socket.assigns.current_scope)

    if connected?(socket) do
      VideoStatusSync.subscribe_all(videos)
    end

    {:ok,
     socket
     |> assign(:page_title, "Datasets")
     |> assign(:query, "")
     |> assign(:status_filter, "all")
     |> assign(:group_filter, "all")
     |> assign(:view, "video")
     |> assign(:all_videos, videos)
     |> assign_thumbnails(videos)
     |> assign_derived()}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> assign_derived()}
  end

  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:status_filter, status) |> assign_derived()}
  end

  def handle_event("filter_group", %{"group" => group}, socket) do
    {:noreply, socket |> assign(:group_filter, group) |> assign_derived()}
  end

  def handle_event("switch_view", %{"view" => view}, socket)
      when view in ["video", "subject", "group"] do
    {:noreply, assign(socket, :view, view)}
  end

  @impl true
  def handle_info({:status, video_id, status}, socket) do
    videos =
      Enum.map(socket.assigns.all_videos, &VideoStatusSync.patch_status(&1, video_id, status))

    {:noreply, socket |> assign(:all_videos, videos) |> assign_derived()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Header stat cards are computed over *all* videos; the list/groups reflect
  # the active search + status filter.
  defp assign_derived(socket) do
    %{all_videos: videos, query: query, status_filter: status, group_filter: group} =
      socket.assigns

    q = query |> String.trim() |> String.downcase()

    filtered =
      videos
      |> Enum.filter(fn v -> status == "all" or v.status == status end)
      |> Enum.filter(fn v -> group == "all" or video_group(v) == group end)
      |> Enum.filter(fn v -> q == "" or matches_query?(v, q) end)

    socket
    |> assign(:summary, Reporting.datasets_summary(videos))
    |> assign(:videos, filtered)
    |> assign(:subject_groups, Reporting.subject_groups(filtered))
    |> assign(:groups_summary, Reporting.groups_summary(filtered))
    |> assign(:available_groups, available_groups(videos))
  end

  defp matches_query?(video, q) do
    [video.filename, video.subject && video.subject.name, video.experiment.name]
    |> Enum.any?(fn s -> s && String.contains?(String.downcase(s), q) end)
  end

  defp video_group(%{subject: %{group: g}}) when is_binary(g) and g != "", do: g
  defp video_group(_), do: nil

  defp available_groups(videos) do
    videos |> Enum.map(&video_group/1) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
  end

  # --- Thumbnails (async, cached per video on disk) ---

  # Shares RoiEdit's per-video frame cache (`uploads/roi_edit_frames/<id>.png`),
  # so a frame extracted here or there is reused. Extraction shells out to
  # Python, so it runs off the socket via assign_async with bounded concurrency;
  # already-cached frames skip the subprocess.
  defp assign_thumbnails(socket, videos) do
    assign_async(socket, :thumbnails, fn ->
      thumbs =
        videos
        |> Task.async_stream(
          fn video -> {video.id, ensure_thumbnail(video)} end,
          max_concurrency: System.schedulers_online(),
          timeout: :timer.seconds(30),
          on_timeout: :kill_task
        )
        |> Enum.reduce(%{}, fn
          {:ok, {id, url}}, acc -> Map.put(acc, id, url)
          {:exit, _reason}, acc -> acc
        end)

      {:ok, %{thumbnails: thumbs}}
    end)
  end

  defp ensure_thumbnail(video) do
    frame_path = Path.join([static_dir(), "uploads", "roi_edit_frames", "#{video.id}.png"])
    web_path = "/uploads/roi_edit_frames/#{video.id}.png"

    cond do
      File.exists?(frame_path) ->
        web_path

      is_binary(video.filepath) and File.exists?(video.filepath) ->
        case MouseTracker.Tracking.FrameExtractor.extract_first_frame(video.filepath, frame_path) do
          {:ok, _meta} -> web_path
          {:error, _} -> nil
        end

      true ->
        nil
    end
  end

  defp static_dir, do: Path.join(:code.priv_dir(:mouse_tracker), "static")

  defp thumb_src(%{ok?: true, result: thumbs}, id), do: Map.get(thumbs, id)
  defp thumb_src(_async, _id), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={:datasets}
      breadcrumb="Workspace"
      page_title="Datasets"
    >
      <div class="mx-auto max-w-[1100px]">
        <div class="flex items-start justify-between">
          <div>
            <h1 class="text-[24px] font-bold text-[#0f1729]">Datasets</h1>
            <p class="mt-1 text-[13px] text-[#667085]">
              Raw videos and tracked trajectories from every experiment.
            </p>
          </div>
          <.button size="lg" shadow navigate={~p"/experiments/new"}>
            <.icon name="hero-arrow-up-tray-micro" class="size-4" /> Upload video
          </.button>
        </div>

        <div class="mt-5 grid grid-cols-2 gap-4 lg:grid-cols-4">
          <.stat_card
            label="Videos"
            value={Integer.to_string(@summary.count)}
            sub="In this workspace"
          />
          <.stat_card
            label="Recording time"
            value={format_hours(@summary.recording_seconds)}
            unit="h"
            sub="Total duration"
          />
          <.stat_card
            label="Tracked"
            value={"#{@summary.tracked} / #{@summary.count}"}
            sub="Finished processing"
          />
          <.storage_card bytes={@summary.storage_bytes} />
        </div>

        <div class="mt-6 flex flex-wrap items-center justify-between gap-3">
          <div class="inline-flex items-center gap-1 rounded-[9px] border border-[#e7e9ee] bg-white p-1">
            <button
              :for={
                {value, label} <- [
                  {"video", "By video"},
                  {"subject", "By subject"},
                  {"group", "By group"}
                ]
              }
              type="button"
              phx-click="switch_view"
              phx-value-view={value}
              class={[
                "rounded-[6px] px-3 py-1.5 text-[12.5px] font-medium transition-colors",
                @view == value && "bg-[#0f1729] text-white",
                @view != value && "text-[#667085] hover:text-[#0f1729]"
              ]}
            >
              {label}
            </button>
          </div>

          <div class="flex flex-wrap items-center gap-3">
            <.search_input
              id="dataset-search"
              query={@query}
              placeholder="Search by file, subject or experiment"
            />

            <form id="dataset-group-filter" phx-change="filter_group">
              <select
                name="group"
                class="rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-2 text-[12.5px] text-[#344054] focus:border-[#CC5500] focus:outline-none"
              >
                <option value="all" selected={@group_filter == "all"}>All groups</option>
                <option :for={g <- @available_groups} value={g} selected={@group_filter == g}>
                  {g}
                </option>
              </select>
            </form>

            <div class="inline-flex items-center gap-1 rounded-[9px] border border-[#e7e9ee] bg-white p-1">
              <button
                :for={{value, label} <- tabs()}
                type="button"
                phx-click="filter"
                phx-value-status={value}
                class={[
                  "rounded-[6px] px-3 py-1.5 text-[12.5px] font-medium transition-colors",
                  @status_filter == value && "bg-[#0f1729] text-white",
                  @status_filter != value && "text-[#667085] hover:text-[#0f1729]"
                ]}
              >
                {label}
              </button>
            </div>
          </div>
        </div>

        <.empty_state
          :if={@videos == []}
          class="mt-6"
          icon="hero-film"
          title={
            if @query != "" or @status_filter != "all",
              do: "No matching videos",
              else: "No videos yet"
          }
          subtitle={
            if @query != "" or @status_filter != "all",
              do: "Try a different search or status filter.",
              else: "Upload locomotion videos through an experiment to build your library."
          }
        >
          <.button
            :if={@query == "" and @status_filter == "all"}
            size="lg"
            class="mt-5"
            navigate={~p"/experiments/new"}
          >
            <.icon name="hero-arrow-up-tray-micro" class="size-4" /> Upload your first video
          </.button>
        </.empty_state>

        <div :if={@videos != [] and @view == "video"} class="mt-4">
          <.video_table videos={@videos} thumbnails={@thumbnails} />
        </div>

        <div :if={@videos != [] and @view == "subject"} class="mt-4 space-y-4">
          <.subject_group :for={group <- @subject_groups} group={group} />
        </div>

        <div :if={@videos != [] and @view == "group"} class="mt-4 space-y-4">
          <.group_card :for={g <- @groups_summary} group={g} />
        </div>
      </div>
    </Layouts.locomo>
    """
  end

  # --- By-video table ---

  attr :videos, :list, required: true
  attr :thumbnails, :any, required: true

  defp video_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-[13px] border border-[#e7e9ee] bg-white shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <table class="w-full min-w-[900px] text-left text-[12.5px]">
        <thead>
          <tr class="border-b border-[#f4f5f7] text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
            <th class="px-[18px] py-3">File</th>
            <th class="px-3 py-3">Subject</th>
            <th class="px-3 py-3">Duration · fps</th>
            <th class="px-3 py-3 text-right">Size</th>
            <th class="px-3 py-3">Calibration</th>
            <th class="px-3 py-3">Status</th>
            <th class="px-3 py-3">Experiment</th>
            <th class="px-[18px] py-3"></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={v <- @videos} class="border-b border-[#f4f5f7] last:border-0 hover:bg-[#fafbfc]">
            <td class="px-[18px] py-3">
              <div class="flex items-center gap-3">
                <div class="flex h-10 w-[64px] shrink-0 items-center justify-center overflow-hidden rounded-[8px] border border-[#eef1f4] bg-[#11161f]">
                  <img
                    :if={thumb_src(@thumbnails, v.id)}
                    src={thumb_src(@thumbnails, v.id)}
                    alt={v.filename}
                    class="h-full w-full object-cover"
                    loading="lazy"
                  />
                  <.icon
                    :if={!thumb_src(@thumbnails, v.id)}
                    name="hero-film"
                    class="size-4 text-[#475467]"
                  />
                </div>
                <div class="min-w-0">
                  <div class="truncate font-data text-[12.5px] font-medium text-[#0f1729]">
                    {v.filename}
                  </div>
                  <div
                    :if={v.status == "done"}
                    class="mt-0.5 truncate font-data text-[11px] text-[#8a93a3]"
                  >
                    {metrics_preview(v)}
                  </div>
                </div>
              </div>
            </td>
            <td class="px-3 py-3">
              <div :if={v.subject} class="flex items-center gap-2">
                <span
                  class="size-2 shrink-0 rounded-full"
                  style={"background:#{subject_color(v.subject.id)}"}
                ></span>
                <div class="min-w-0">
                  <div class="truncate font-data text-[12px] text-[#344054]">{v.subject.name}</div>
                  <div :if={v.subject.genotype} class="truncate text-[10.5px] text-[#98a2b3]">
                    {v.subject.genotype}
                  </div>
                  <div :if={v.subject.group} class="truncate text-[10.5px] text-[#98a2b3]">
                    {v.subject.group}
                  </div>
                </div>
              </div>
              <span :if={!v.subject} class="text-[12px] text-[#98a2b3]">—</span>
            </td>
            <td class="px-3 py-3 font-data text-[12px] text-[#344054]">{duration_fps(v)}</td>
            <td class="px-3 py-3 text-right font-data text-[12px] text-[#344054]">
              {format_size(v.file_size_bytes)}
            </td>
            <td class="px-3 py-3">
              <span :if={calibration_px_per_cm(v)} class="font-data text-[12px] text-[#344054]">
                {calibration_px_per_cm(v)}
              </span>
              <span
                :if={!calibration_px_per_cm(v)}
                class="inline-flex items-center gap-1.5 text-[11.5px] text-[#98a2b3]"
              >
                <span class="size-1.5 rounded-full bg-[#cbd2dc]"></span> Not set
              </span>
            </td>
            <td class="px-3 py-3"><.status_pill status={v.status} /></td>
            <td class="px-3 py-3">
              <.link
                navigate={~p"/experiments/#{v.experiment.id}"}
                class="truncate text-[12px] text-[#475467] underline-offset-2 hover:text-[#0f1729] hover:underline"
              >
                {v.experiment.name}
              </.link>
            </td>
            <td class="px-[18px] py-3 text-right">
              <.link navigate={row_action_path(v)} class="text-[#b0b7c1] hover:text-[#667085]">
                <.icon name="hero-chevron-right-mini" class="size-4" />
              </.link>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # --- By-subject group ---

  attr :group, :map, required: true

  defp subject_group(assigns) do
    ~H"""
    <div class="rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <div class="flex items-center gap-2">
        <span
          class="size-2.5 shrink-0 rounded-full"
          style={"background:#{subject_color(@group.subject && @group.subject.id)}"}
        ></span>
        <span class="font-data text-[14px] font-bold text-[#0f1729]">
          {(@group.subject && @group.subject.name) || "No subject"}
        </span>
        <span :if={@group.subject && @group.subject.genotype} class="text-[11.5px] text-[#98a2b3]">
          {@group.subject.genotype}
        </span>
        <span :if={@group.subject && @group.subject.group} class="text-[11.5px] text-[#98a2b3]">
          {@group.subject.group}
        </span>
        <span class="ml-auto font-data text-[11.5px] text-[#8a93a3]">
          {length(@group.videos)} video(s) · {@group.aggregate.n} tracked
        </span>
      </div>

      <.metric_stat_cards
        :if={@group.aggregate.n > 0}
        metrics={@group.aggregate.metrics}
        fields={[
          %{key: :distance_cm, label: "Distance", unit: "cm"},
          %{key: :speed_mean_cm, label: "Mean speed", unit: "cm/s"},
          %{key: :thigmotaxis_pct, label: "Thigmotaxis", unit: "%"},
          %{key: :immobility_seconds, label: "Immobility", unit: "s"}
        ]}
        class="mt-3 grid grid-cols-2 gap-3 lg:grid-cols-4"
      />

      <div class="mt-3 divide-y divide-[#f4f5f7]">
        <div :for={v <- @group.videos} class="flex items-center gap-3 py-2">
          <.status_pill status={v.status} />
          <span class="min-w-0 flex-1 truncate font-data text-[12px] text-[#344054]">{v.filename}</span>
          <span class="hidden font-data text-[11.5px] text-[#8a93a3] sm:inline">{duration_fps(v)}</span>
          <.link
            navigate={~p"/experiments/#{v.experiment.id}"}
            class="truncate text-[11.5px] text-[#475467] hover:text-[#0f1729]"
          >
            {v.experiment.name}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  # --- By-group card ---

  attr :group, :map, required: true

  defp group_card(assigns) do
    ~H"""
    <div class="rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <div class="flex items-center gap-2">
        <span class="font-data text-[14px] font-bold text-[#0f1729]">
          {@group.group || "Ungrouped"}
        </span>
        <span class="text-[11.5px] text-[#98a2b3]">{length(@group.subjects)} subject(s)</span>
        <span class="ml-auto font-data text-[11.5px] text-[#8a93a3]">
          {length(@group.videos)} video(s) · {@group.aggregate.n} tracked
        </span>
      </div>

      <.metric_stat_cards
        :if={@group.aggregate.n > 0}
        metrics={@group.aggregate.metrics}
        fields={[
          %{key: :distance_cm, label: "Distance", unit: "cm"},
          %{key: :speed_mean_cm, label: "Mean speed", unit: "cm/s"},
          %{key: :thigmotaxis_pct, label: "Thigmotaxis", unit: "%"},
          %{key: :immobility_seconds, label: "Immobility", unit: "s"}
        ]}
        class="mt-3 grid grid-cols-2 gap-3 lg:grid-cols-4"
      />

      <div class="mt-3 divide-y divide-[#f4f5f7]">
        <div :for={v <- @group.videos} class="flex items-center gap-3 py-2">
          <.status_pill status={v.status} />
          <span class="min-w-0 flex-1 truncate font-data text-[12px] text-[#344054]">
            <span :if={v.subject}>{v.subject.name} · </span>{v.filename}
          </span>
          <span class="hidden font-data text-[11.5px] text-[#8a93a3] sm:inline">{duration_fps(v)}</span>
          <.link
            navigate={~p"/experiments/#{v.experiment.id}"}
            class="truncate text-[11.5px] text-[#475467] hover:text-[#0f1729]"
          >
            {v.experiment.name}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :bytes, :integer, required: true

  # Storage card with a proportion bar toward an informational 200 GB reference.
  defp storage_card(assigns) do
    cap = 200 * 1024 * 1024 * 1024
    pct = if assigns.bytes > 0, do: min(assigns.bytes / cap * 100, 100.0), else: 0.0
    assigns = assign(assigns, pct: pct)

    ~H"""
    <div class="rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <div class="text-[10.5px] font-semibold uppercase tracking-wide text-[#8a93a3]">Storage</div>
      <div class="mt-2 flex items-baseline gap-1">
        <span class="font-data text-[32px] font-semibold leading-none text-[#0f1729]">
          {format_gb(@bytes)}
        </span>
        <span class="font-data text-[13px] text-[#98a2b3]">GB</span>
      </div>
      <div class="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-[#f2f4f7]">
        <div class="h-full rounded-full bg-[#CC5500]" style={"width:#{@pct}%"}></div>
      </div>
    </div>
    """
  end

  # --- helpers ---

  defp tabs, do: @tabs

  defp row_action_path(%{status: "done", experiment_id: exp_id, id: id}),
    do: ~p"/experiments/#{exp_id}/results?#{[video: id]}"

  defp row_action_path(%{status: status, id: id})
       when status in ["processing", "pending", "error"],
       do: ~p"/videos/#{id}/processing"

  defp metrics_preview(%{tracking_result: %{distance_cm: d, speed_mean_cm: s}}),
    do: "#{fmt(d)} cm · #{fmt(s)} cm/s"

  defp metrics_preview(_), do: ""

  defp duration_fps(%{duration_seconds: nil, fps: nil}), do: "—"
  defp duration_fps(%{duration_seconds: d, fps: nil}), do: format_duration(d)
  defp duration_fps(%{duration_seconds: nil, fps: fps}), do: "#{fps} fps"
  defp duration_fps(%{duration_seconds: d, fps: fps}), do: "#{format_duration(d)} · #{fps} fps"

  defp format_duration(seconds) when is_number(seconds) do
    total = round(seconds)
    minutes = div(total, 60)
    secs = rem(total, 60)
    "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp format_duration(_), do: "—"

  defp calibration_px_per_cm(%{calibration: %{px_per_10cm: px}}) when is_number(px) and px > 0,
    do: "#{fmt(px / 10)} px/cm"

  defp calibration_px_per_cm(_), do: nil

  defp format_size(bytes) when is_integer(bytes) and bytes > 0 do
    cond do
      bytes >= 1024 * 1024 * 1024 -> "#{fmt(bytes / (1024 * 1024 * 1024))} GB"
      bytes >= 1024 * 1024 -> "#{fmt(bytes / (1024 * 1024))} MB"
      bytes >= 1024 -> "#{fmt(bytes / 1024)} KB"
      true -> "#{bytes} B"
    end
  end

  defp format_size(_), do: "—"

  defp format_hours(seconds) when is_number(seconds) and seconds > 0,
    do: :erlang.float_to_binary(seconds / 3600, decimals: 1)

  defp format_hours(_), do: "0.0"

  defp format_gb(bytes) when is_number(bytes) and bytes > 0,
    do: :erlang.float_to_binary(bytes / (1024 * 1024 * 1024), decimals: 1)

  defp format_gb(_), do: "0.0"
end
