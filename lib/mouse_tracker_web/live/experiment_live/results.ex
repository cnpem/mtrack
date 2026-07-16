defmodule MouseTrackerWeb.ExperimentLive.Results do
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments

  # Only the per-video tab is wired to real data for now. The batch/subject
  # aggregations depend on cohort grouping (Saline/CNO `treatment_group`) that
  # the schema does not model yet, so they render as disabled "coming soon"
  # tabs. See CLAUDE.md Sprint 3.
  @tabs [
    {"video", "Por vídeo", true},
    {"batch", "Média da batch", false},
    {"subject", "Por subject", false}
  ]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    experiment = Experiments.get_experiment_for_results!(socket.assigns.current_scope, id)
    done_videos = Enum.filter(experiment.videos, &(&1.status == "done"))

    {:ok,
     socket
     |> assign(:page_title, "Results — #{experiment.name}")
     |> assign(:experiment, experiment)
     |> assign(:done_videos, done_videos)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in ["video", "batch", "subject"], do: params["tab"], else: "video"
    selected = select_video(socket.assigns.done_videos, params["video"])

    {:noreply,
     socket
     |> assign(:tab, tab)
     |> assign(:selected_video, selected)}
  end

  # Picks the video whose results are shown: the `?video=` one if it is done,
  # otherwise the first done video (or nil when the experiment has none).
  defp select_video(done_videos, video_param) do
    case Integer.parse(video_param || "") do
      {id, ""} -> Enum.find(done_videos, List.first(done_videos), &(&1.id == id))
      _ -> List.first(done_videos)
    end
  end

  @impl true
  def handle_event("select_video", %{"video" => video_id}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/experiments/#{socket.assigns.experiment.id}/results?#{[video: video_id]}"
     )}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    params =
      [tab: tab] ++
        if(socket.assigns.selected_video, do: [video: socket.assigns.selected_video.id], else: [])

    {:noreply,
     push_patch(socket, to: ~p"/experiments/#{socket.assigns.experiment.id}/results?#{params}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={:experiments}
      breadcrumb={@experiment.name}
      page_title="Results"
    >
      <div class="mx-auto max-w-[1000px]">
        <.link
          navigate={~p"/experiments/#{@experiment.id}"}
          class="inline-flex items-center gap-1 text-[12.5px] text-[#667085] hover:text-[#0f1729]"
        >
          <.icon name="hero-chevron-left-micro" class="size-4" /> {@experiment.name}
        </.link>

        <div class="mt-3 flex items-center gap-3">
          <h1 class="text-[23px] font-bold text-[#0f1729]">Results</h1>
          <span
            :if={@done_videos != []}
            class="inline-flex items-center gap-1.5 rounded-[20px] bg-[#fbeee4] px-2.5 py-1 text-[11.5px] font-semibold text-[#b34a00]"
          >
            <span class="size-1.5 rounded-full bg-[#CC5500]"></span> Analysis complete
          </span>
        </div>
        <p class="mt-1 font-data text-[12px] text-[#8a93a3]">
          {length(@done_videos)} of {length(@experiment.videos)} videos analyzed
        </p>

        <div class="mt-5 inline-flex items-center gap-1 rounded-[9px] border border-[#e7e9ee] bg-white p-1">
          <button
            :for={{value, label, enabled} <- tabs()}
            type="button"
            disabled={not enabled}
            phx-click={enabled && "switch_tab"}
            phx-value-tab={value}
            title={not enabled && "Coming soon"}
            class={[
              "rounded-[6px] px-3 py-1.5 text-[12.5px] font-medium transition-colors",
              @tab == value && "bg-[#0f1729] text-white",
              @tab != value && enabled && "text-[#667085] hover:text-[#0f1729]",
              not enabled && "cursor-not-allowed text-[#c3c9d2]"
            ]}
          >
            {label}
            <span :if={not enabled} class="ml-1 text-[10px] text-[#c3c9d2]">soon</span>
          </button>
        </div>

        <div
          :if={@done_videos == []}
          class="mt-5 flex flex-col items-center rounded-[13px] border border-dashed border-[#d4d8df] bg-white px-6 py-16 text-center"
        >
          <div class="flex size-12 items-center justify-center rounded-full bg-[#f2f4f7] text-[#98a2b3]">
            <.icon name="hero-chart-bar" class="size-6" />
          </div>
          <h2 class="mt-4 text-[15px] font-bold text-[#0f1729]">No analyzed videos yet</h2>
          <p class="mt-1 max-w-sm text-[13px] text-[#667085]">
            Results appear here once a video finishes processing.
          </p>
        </div>

        <div :if={@done_videos != []} class="mt-5">
          <.video_results
            :if={@selected_video}
            video={@selected_video}
            done_videos={@done_videos}
          />
        </div>
      </div>
    </Layouts.locomo>
    """
  end

  attr :video, :map, required: true
  attr :done_videos, :list, required: true

  defp video_results(assigns) do
    assigns = assign(assigns, :result, assigns.video.tracking_result)

    ~H"""
    <div class="flex flex-wrap items-center gap-2 rounded-[13px] border border-[#e7e9ee] bg-white p-2">
      <span class="px-2 text-[11px] font-semibold uppercase tracking-wide text-[#98a2b3]">
        Video
      </span>
      <button
        :for={v <- @done_videos}
        type="button"
        phx-click="select_video"
        phx-value-video={v.id}
        class={[
          "inline-flex items-center gap-2 rounded-[8px] px-3 py-1.5 text-[12.5px] font-medium transition-colors",
          v.id == @video.id && "bg-[#0f1729] text-white",
          v.id != @video.id && "text-[#667085] hover:bg-[#f2f4f7]"
        ]}
      >
        <span class="size-2 rounded-full" style={"background:#{subject_color(v.subject_id)}"}></span>
        <span class="font-data">{v.filename}</span>
      </button>
    </div>

    <div :if={@result} class="mt-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
      <.stat_card
        label="Distance traveled"
        value={fmt(@result.distance_cm)}
        unit="cm"
        sub="Total path length"
      />
      <.stat_card
        label="Mean speed"
        value={fmt(@result.speed_mean_cm)}
        unit="cm/s"
        sub="Average over session"
      />
      <.stat_card
        label="Median speed"
        value={fmt(@result.speed_median_cm)}
        unit="cm/s"
        sub="Typical speed"
      />
      <.stat_card
        label="Time in ROI"
        value={fmt(total_roi_seconds(@result))}
        unit="s"
        sub="Across all zones"
      />
    </div>

    <div :if={@result} class="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
      <.plot_card title="Occupancy heatmap" src={@result.heatmap_path} />
      <.plot_card title="Speed profile" src={@result.speed_profile_path} />
    </div>

    <div
      :if={@result && @result.roi_times != []}
      class="mt-4 rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]"
    >
      <div class="flex items-center justify-between">
        <div class="text-[13px] font-bold text-[#0f1729]">Time in ROI zones</div>
        <div class="font-data text-[11.5px] text-[#8a93a3]">
          total {fmt(total_roi_seconds(@result))} s
        </div>
      </div>

      <div class="mt-3 grid grid-cols-[1.4fr_1fr_1.6fr] gap-3 border-b border-[#f4f5f7] pb-2 text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
        <div>Zone</div>
        <div>Time</div>
        <div>Share of session</div>
      </div>

      <div
        :for={rt <- @result.roi_times}
        class="grid grid-cols-[1.4fr_1fr_1.6fr] items-center gap-3 border-b border-[#f4f5f7] py-2.5 last:border-0"
      >
        <div class="text-[13px] font-medium text-[#0f1729]">{rt.roi.name}</div>
        <div class="font-data text-[12.5px] text-[#344054]">{fmt(rt.seconds)} s</div>
        <div class="flex items-center gap-2">
          <div class="h-2 flex-1 overflow-hidden rounded-full bg-[#f2f4f7]">
            <div
              class="h-full rounded-full bg-[#CC5500]"
              style={"width:#{share_pct(rt.seconds, @video)}%"}
            >
            </div>
          </div>
          <span class="w-12 shrink-0 text-right font-data text-[11.5px] text-[#667085]">
            {share_label(rt.seconds, @video)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :src, :string, default: nil

  defp plot_card(assigns) do
    ~H"""
    <div class="rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <div class="text-[13px] font-bold text-[#0f1729]">{@title}</div>
      <div class="mt-3 overflow-hidden rounded-[10px] border border-[#f4f5f7] bg-[#11161f]">
        <img
          :if={@src}
          src={@src}
          alt={@title}
          class="block h-auto w-full"
          loading="lazy"
        />
        <div
          :if={!@src}
          class="flex h-48 items-center justify-center font-data text-[12px] text-[#667085]"
        >
          not available
        </div>
      </div>
    </div>
    """
  end

  # --- helpers ---

  defp tabs, do: @tabs

  defp total_roi_seconds(%{roi_times: roi_times}) when is_list(roi_times) do
    roi_times |> Enum.map(& &1.seconds) |> Enum.sum()
  end

  defp total_roi_seconds(_), do: 0.0

  # Share of the session spent in a zone. Falls back to 0 when the video has no
  # known duration (older records may lack `duration_seconds`).
  defp share_pct(_seconds, %{duration_seconds: d}) when d in [nil, 0, 0.0], do: 0.0

  defp share_pct(seconds, %{duration_seconds: duration}) do
    min(seconds / duration * 100, 100.0)
  end

  defp share_label(_seconds, %{duration_seconds: d}) when d in [nil, 0, 0.0], do: "—"
  defp share_label(seconds, video), do: "#{fmt(share_pct(seconds, video))}%"

  defp fmt(nil), do: "—"
  defp fmt(n) when is_integer(n), do: Integer.to_string(n)
  defp fmt(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
end
