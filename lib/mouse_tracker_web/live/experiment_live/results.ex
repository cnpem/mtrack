defmodule MouseTrackerWeb.ExperimentLive.Results do
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments
  alias MouseTracker.Experiments.Reporting

  @tabs [
    {"video", "Per video", true},
    {"subject", "Per subject", true}
  ]

  @metrics_views ["average", "per_video"]

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    experiment = Experiments.get_experiment_for_results!(socket.assigns.current_scope, id)
    done_videos = Enum.filter(experiment.videos, &(&1.status == "done"))

    {:ok,
     socket
     |> assign(:page_title, "Results — #{experiment.name}")
     |> assign(:experiment, experiment)
     |> assign(:done_videos, done_videos)
     |> assign(:experiment_subjects, Experiments.experiment_subjects(experiment))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in ["video", "subject"], do: params["tab"], else: "video"
    selected = select_video(socket.assigns.done_videos, params["video"])

    socket =
      socket
      |> assign(:tab, tab)
      |> assign(:selected_video, selected)

    socket = if tab == "subject", do: assign_subject_tab(socket, params), else: socket

    {:noreply, socket}
  end

  # Builds everything the "Por subject" tab needs: which subject is selected
  # (defaults to the selected video's subject, else the experiment's first
  # subject), which experiments it can be filtered to (it may have "done"
  # videos in experiments other than this one — Subject is a reusable, shared
  # resource, see CLAUDE.md), and the aggregated data for that selection.
  defp assign_subject_tab(socket, params) do
    subjects = socket.assigns.experiment_subjects

    subject_id =
      case Integer.parse(params["subject"] || "") do
        {id, ""} -> id
        _ -> default_subject_id(subjects, socket.assigns.selected_video)
      end

    metrics_view =
      if params["metrics_view"] in @metrics_views, do: params["metrics_view"], else: "average"

    socket =
      socket
      |> assign(:subject, Enum.find(subjects, &(&1.id == subject_id)))
      |> assign(:metrics_view, metrics_view)

    if socket.assigns.subject do
      scope = socket.assigns.current_scope
      scope_experiment_id = parse_int(params["scope_experiment"])

      subject_experiments = Reporting.subject_experiments(scope, subject_id)
      subject_videos = Reporting.subject_result_videos(scope, subject_id, scope_experiment_id)

      socket
      |> assign(:scope_experiment_id, scope_experiment_id)
      |> assign(:subject_experiments, subject_experiments)
      |> assign(:subject_videos, subject_videos)
      |> assign(:calibration_groups, Reporting.group_by_calibration(subject_videos))
      |> assign(:subject_aggregate, Reporting.subject_metric_aggregate(subject_videos))
    else
      socket
      |> assign(:scope_experiment_id, nil)
      |> assign(:subject_experiments, [])
      |> assign(:subject_videos, [])
      |> assign(:calibration_groups, [])
      |> assign(:subject_aggregate, nil)
    end
  end

  defp default_subject_id([], _selected_video), do: nil

  defp default_subject_id([%{id: id} | _] = subjects, selected_video) do
    case selected_video do
      %{subject_id: sid} when not is_nil(sid) ->
        if Enum.any?(subjects, &(&1.id == sid)), do: sid, else: id

      _ ->
        id
    end
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

  def handle_event("select_subject", %{"subject" => subject_id}, socket) do
    {:noreply, patch_subject_tab(socket, subject: subject_id, scope_experiment: "all")}
  end

  def handle_event("set_scope_experiment", %{"scope_experiment" => scope_experiment}, socket) do
    {:noreply, patch_subject_tab(socket, scope_experiment: scope_experiment)}
  end

  def handle_event("switch_metrics_view", %{"view" => view}, socket) do
    {:noreply, patch_subject_tab(socket, metrics_view: view)}
  end

  # Patches the URL for the "Por subject" tab, keeping the current
  # subject/scope/metrics-view selection except for whatever `overrides`.
  defp patch_subject_tab(socket, overrides) do
    base = [
      tab: "subject",
      subject: socket.assigns.subject && socket.assigns.subject.id,
      scope_experiment: socket.assigns.scope_experiment_id || "all",
      metrics_view: socket.assigns.metrics_view
    ]

    params = patch_params(base, overrides)

    push_patch(socket, to: ~p"/experiments/#{socket.assigns.experiment.id}/results?#{params}")
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
            {label} <span :if={not enabled} class="ml-1 text-[10px] text-[#c3c9d2]">soon</span>
          </button>
        </div>

        <.empty_state
          :if={@done_videos == []}
          class="mt-5"
          icon="hero-chart-bar"
          title="No analyzed videos yet"
          subtitle="Results appear here once a video finishes processing."
        />

        <div :if={@done_videos != [] and @tab == "video"} class="mt-5">
          <.video_results
            :if={@selected_video}
            video={@selected_video}
            done_videos={@done_videos}
          />
        </div>

        <div :if={@tab == "subject"} class="mt-5">
          <.subject_results
            :if={@subject}
            subject={@subject}
            experiment_subjects={@experiment_subjects}
            subject_experiments={@subject_experiments}
            scope_experiment_id={@scope_experiment_id}
            subject_videos={@subject_videos}
            calibration_groups={@calibration_groups}
            aggregate={@subject_aggregate}
            metrics_view={@metrics_view}
          />
          <.empty_state
            :if={!@subject}
            title="No subject to show"
            subtitle="This experiment's videos have no subject assigned yet."
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
        value={fmt(Reporting.total_roi_seconds(@result))}
        unit="s"
        sub="Across all zones"
      />
    </div>

    <div :if={@result} class="mt-4 grid grid-cols-2 gap-4 lg:grid-cols-4">
      <.stat_card
        label="Max speed"
        value={fmt(@result.speed_max_cm)}
        unit="cm/s"
        sub="Peak instantaneous"
      />
      <.stat_card
        label="Thigmotaxis"
        value={fmt(@result.thigmotaxis_pct)}
        unit="%"
        sub="Time near the wall"
      />
      <.stat_card
        label="Path tortuosity"
        value={fmt(@result.path_tortuosity)}
        sub="Path length / displacement"
      />
      <.stat_card
        label="Immobility"
        value={fmt(@result.immobility_seconds)}
        unit="s"
        sub="Speed < 2 cm/s"
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
          total {fmt(Reporting.total_roi_seconds(@result))} s
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
  attr :sub, :string, default: nil
  attr :src, :string, default: nil

  defp plot_card(assigns) do
    ~H"""
    <div class="rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <div class="text-[13px] font-bold text-[#0f1729]">{@title}</div>

      <div :if={@sub} class="text-[11.5px] text-[#8a93a3]">{@sub}</div>

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

  attr :subject, :map, required: true
  attr :experiment_subjects, :list, required: true
  attr :subject_experiments, :list, required: true
  attr :scope_experiment_id, :integer, default: nil
  attr :subject_videos, :list, required: true
  attr :calibration_groups, :list, required: true
  attr :aggregate, :map, default: nil
  attr :metrics_view, :string, required: true

  defp subject_results(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2 rounded-[13px] border border-[#e7e9ee] bg-white p-2">
      <span class="px-2 text-[11px] font-semibold uppercase tracking-wide text-[#98a2b3]">
        Subject
      </span>

      <button
        :for={s <- @experiment_subjects}
        type="button"
        phx-click="select_subject"
        phx-value-subject={s.id}
        class={[
          "inline-flex items-center gap-2 rounded-[8px] px-3 py-1.5 text-[12.5px] font-medium transition-colors",
          s.id == @subject.id && "bg-[#0f1729] text-white",
          s.id != @subject.id && "text-[#667085] hover:bg-[#f2f4f7]"
        ]}
      >
        <span class="size-2 rounded-full" style={"background:#{subject_color(s.id)}"}></span>
        <span class="font-data">{s.name}</span>
      </button>
    </div>

    <div class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-[13px] border border-[#e7e9ee] bg-white p-3">
      <div class="text-[12.5px] text-[#667085]">
        <span class="font-data font-semibold text-[#0f1729]">{length(@subject_videos)}</span>
        analyzed video(s) for <span class="font-medium text-[#0f1729]">{@subject.name}</span>
        across
        <span class="font-data font-semibold text-[#0f1729]">{length(@subject_experiments)}</span>
        experiment(s)
      </div>

      <form id="subject-scope-experiment" phx-change="set_scope_experiment">
        <select
          name="scope_experiment"
          class="rounded-[6px] border border-[#e7e9ee] bg-white px-2.5 py-1.5 font-data text-[12px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
        >
          <option value="all" selected={@scope_experiment_id == nil}>All experiments</option>

          <option
            :for={exp <- @subject_experiments}
            value={exp.id}
            selected={@scope_experiment_id == exp.id}
          >
            {exp.name}
          </option>
        </select>
      </form>
    </div>

    <.empty_state
      :if={@subject_videos == []}
      class="mt-4"
      title="No analyzed videos in this scope"
      subtitle="Pick a different subject or widen the experiment filter."
    />

    <div :if={@subject_videos != []}>
      <div class="mt-4 flex flex-wrap gap-6">
        <div :for={{calibration, videos} <- @calibration_groups} class="w-full sm:w-[380px]">
          <div class="mb-2 flex items-center gap-2 text-[13px] font-bold text-[#0f1729]">
            <.icon name="hero-squares-2x2" class="size-4 text-[#98a2b3]" /> {calibration_label(
              calibration
            )}
            <span class="font-data text-[11.5px] font-normal text-[#8a93a3]">
              {length(videos)} video(s)
            </span>
          </div>

          <div class="grid grid-cols-1 gap-4">
            <.plot_card
              :for={v <- videos}
              title={v.filename}
              sub={v.experiment.name}
              src={v.tracking_result && v.tracking_result.heatmap_path}
            />
          </div>
        </div>
      </div>

      <div class="mt-5 inline-flex items-center gap-1 rounded-[9px] border border-[#e7e9ee] bg-white p-1">
        <button
          :for={{value, label} <- [{"average", "Average"}, {"per_video", "Per video"}]}
          type="button"
          phx-click="switch_metrics_view"
          phx-value-view={value}
          class={[
            "rounded-[6px] px-3 py-1.5 text-[12.5px] font-medium transition-colors",
            @metrics_view == value && "bg-[#0f1729] text-white",
            @metrics_view != value && "text-[#667085] hover:text-[#0f1729]"
          ]}
        >
          {label}
        </button>
      </div>
      <.subject_average :if={@metrics_view == "average"} aggregate={@aggregate} />
      <.subject_per_video :if={@metrics_view == "per_video"} videos={@subject_videos} />
    </div>
    """
  end

  attr :aggregate, :map, default: nil

  defp subject_average(assigns) do
    ~H"""
    <div :if={@aggregate} class="mt-4">
      <p class="font-data text-[11.5px] text-[#8a93a3]">
        Mean ± SD across {@aggregate.n} video(s)
      </p>

      <.metric_stat_cards
        metrics={@aggregate.metrics}
        fields={[
          %{key: :distance_cm, label: "Distance traveled", unit: "cm", sub: "Total path length"},
          %{key: :speed_mean_cm, label: "Mean speed", unit: "cm/s", sub: "Average over session"},
          %{key: :speed_median_cm, label: "Median speed", unit: "cm/s", sub: "Typical speed"},
          %{key: :speed_max_cm, label: "Max speed", unit: "cm/s", sub: "Peak instantaneous"},
          %{key: :thigmotaxis_pct, label: "Thigmotaxis", unit: "%", sub: "Time near the wall"},
          %{key: :path_tortuosity, label: "Path tortuosity", sub: "Path length / displacement"},
          %{key: :immobility_seconds, label: "Immobility", unit: "s", sub: "Speed < 2 cm/s"}
        ]}
        class="mt-2 grid grid-cols-2 gap-4 lg:grid-cols-4"
      />

      <div
        :if={@aggregate.roi_zones != []}
        class="mt-4 rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]"
      >
        <div class="text-[13px] font-bold text-[#0f1729]">Time in ROI zones</div>

        <div class="mt-3 grid grid-cols-[1.4fr_1fr_1fr] gap-3 border-b border-[#f4f5f7] pb-2 text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
          <div>Zone</div>

          <div>Avg. time</div>

          <div>Avg. share of session</div>
        </div>

        <div
          :for={zone <- @aggregate.roi_zones}
          class="grid grid-cols-[1.4fr_1fr_1fr] items-center gap-3 border-b border-[#f4f5f7] py-2.5 last:border-0"
        >
          <div class="text-[13px] font-medium text-[#0f1729]">{zone.name}</div>

          <div class="font-data text-[12.5px] text-[#344054]">{fmt(zone.avg_seconds)} s</div>

          <div class="font-data text-[12.5px] text-[#344054]">
            {if zone.avg_share_pct, do: "#{fmt(zone.avg_share_pct)}%", else: "—"}
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :videos, :list, required: true

  defp subject_per_video(assigns) do
    ~H"""
    <div class="mt-4 overflow-x-auto rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]">
      <table class="w-full min-w-[800px] text-left text-[12.5px]">
        <thead>
          <tr class="border-b border-[#f4f5f7] text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
            <th class="pb-2">Experiment</th>

            <th class="pb-2">Video</th>

            <th class="pb-2">Distance</th>

            <th class="pb-2">Mean speed</th>

            <th class="pb-2">Thigmotaxis</th>

            <th class="pb-2">Tortuosity</th>

            <th class="pb-2">Immobility</th>

            <th class="pb-2">Time in ROI</th>
          </tr>
        </thead>

        <tbody>
          <tr :for={v <- @videos} class="border-b border-[#f4f5f7] last:border-0">
            <td class="py-2.5 text-[#344054]">{v.experiment.name}</td>

            <td class="py-2.5 font-data text-[#0f1729]">{v.filename}</td>

            <td class="py-2.5 font-data text-[#344054]">
              {fmt(v.tracking_result && v.tracking_result.distance_cm)} cm
            </td>

            <td class="py-2.5 font-data text-[#344054]">
              {fmt(v.tracking_result && v.tracking_result.speed_mean_cm)} cm/s
            </td>

            <td class="py-2.5 font-data text-[#344054]">
              {fmt(v.tracking_result && v.tracking_result.thigmotaxis_pct)}%
            </td>

            <td class="py-2.5 font-data text-[#344054]">
              {fmt(v.tracking_result && v.tracking_result.path_tortuosity)}
            </td>

            <td class="py-2.5 font-data text-[#344054]">
              {fmt(v.tracking_result && v.tracking_result.immobility_seconds)} s
            </td>

            <td class="py-2.5 font-data text-[#344054]">
              {fmt(v.tracking_result && Reporting.total_roi_seconds(v.tracking_result))} s
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # --- helpers ---

  defp tabs, do: @tabs

  # Bar width falls back to 0 when the session's share can't be computed
  # (older videos may lack `duration_seconds`) — see `Reporting.share_of_session/2`.
  defp share_pct(seconds, video),
    do: Reporting.share_of_session(seconds, video.duration_seconds) || 0.0

  defp share_label(seconds, video) do
    case Reporting.share_of_session(seconds, video.duration_seconds) do
      nil -> "—"
      pct -> "#{fmt(pct)}%"
    end
  end

  defp calibration_label(nil), do: "No calibration assigned"
  defp calibration_label(%{name: name}) when is_binary(name) and name != "", do: name
  defp calibration_label(%{id: id}), do: "Calibration ##{id}"
end
