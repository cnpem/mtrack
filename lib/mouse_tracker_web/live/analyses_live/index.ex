defmodule MouseTrackerWeb.AnalysesLive.Index do
  @moduledoc """
  Analyses (`/analyses`): compare a tracked metric across a Subject's sessions
  (Subject is a reusable, shared resource — see CLAUDE.md), with four
  switchable views:

    * **Trend** — the metric over each subject's chronological "done" sessions,
      overlaid; X aligns by *session index* (1st next to 1st...), not calendar
      date, since subjects rarely share a timeline.
    * **Per subject (box)** — one boxplot per subject over that subject's
      sessions, colored by the subject's group.
    * **Per group (box)** — one boxplot per group, with a named dot per
      (subject, experiment) pair (each dot = a subject's mean within one
      experiment).
    * **Speed dist. (box)** — one boxplot per subject built from the *per-frame*
      speed samples (`tracking_result.speed_samples`) pooled across its
      sessions — the true instantaneous-speed distribution, colored by group.

  Filters are a hierarchy: **Experiment** is the first-class lens; picking a
  **Group** bulk-adds every member subject in that experiment; **Subjects** are
  then added/removed individually. `selected_subjects` is the single source of
  truth for what's plotted.

  All charts are hand-rolled inline SVG (`LocomoComponents.trend_chart/1` /
  `box_plot/1`) — there is no charting library in this app; the data here is
  plain Postgres numeric data (unlike the heatmap/speed-profile PNGs, which
  Python generates from per-frame data this page doesn't have).
  """
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments
  alias MouseTracker.Experiments.{Subjects, Reporting}

  @metrics [
    {"distance_cm", "Distance traveled", "cm"},
    {"speed_mean_cm", "Mean speed", "cm/s"},
    {"speed_median_cm", "Median speed", "cm/s"},
    {"speed_max_cm", "Max speed", "cm/s"},
    {"thigmotaxis_pct", "Thigmotaxis", "%"},
    {"path_tortuosity", "Path tortuosity", nil},
    {"immobility_seconds", "Immobility", "s"}
  ]
  @metric_keys Enum.map(@metrics, &elem(&1, 0))
  @views ~w(trend subject_box group_box speed_box)

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "Analyses")
     |> assign(:experiments, Experiments.list_experiments(scope))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_analysis(socket, params)}
  end

  defp assign_analysis(socket, params) do
    scope = socket.assigns.current_scope
    # Reloaded on every params change (not memoized at mount) so a subject's
    # `group` edited elsewhere — e.g. Pipeline Settings — is reflected on the
    # next interaction, instead of being frozen to whatever it was when the page
    # first mounted. Cheap, indexed query.
    all_subjects = Subjects.list_subjects(scope)

    experiment_id = parse_int(params["experiment"])
    view = if params["view"] in @views, do: params["view"], else: "trend"
    metric = if params["metric"] in @metric_keys, do: params["metric"], else: "distance_cm"
    log1p = params["log1p"] == "1"

    selected_subjects = selected_subjects(params["subjects"], all_subjects)
    groups = Reporting.experiment_groups(scope, experiment_id)
    selected_groups = selected_groups(params["groups"], groups)

    # Each selected subject's scoped "done" videos are fetched once and reused
    # for the trend series, both box views and the table (no N+1, no refetch).
    per_subject =
      Enum.map(selected_subjects, fn subject ->
        videos = Reporting.subject_result_videos(scope, subject.id, experiment_id)

        %{
          subject: subject,
          videos: videos,
          points: Reporting.metric_series(videos, metric)
        }
      end)

    per_group =
      Enum.map(selected_groups, fn group ->
        %{
          group: group,
          points: Reporting.group_metric_series(scope, group, metric, experiment_id)
        }
      end)

    socket
    |> assign(:subjects, all_subjects)
    |> assign(:experiment_id, experiment_id)
    |> assign(:view, view)
    |> assign(:metric, metric)
    |> assign(:log1p, log1p)
    |> assign(:groups, groups)
    |> assign(:selected_subjects, selected_subjects)
    |> assign(:selected_groups, selected_groups)
    |> assign(:picker_subjects, Reporting.experiment_subjects(scope, experiment_id))
    |> assign(:trend_series, subject_series(per_subject) ++ group_series(per_group))
    |> assign(:subject_categories, subject_categories(per_subject, metric))
    |> assign(:group_categories, group_categories(per_subject, metric))
    |> assign(:speed_categories, speed_categories(per_subject))
    |> assign(:ungrouped_selected?, Enum.any?(selected_subjects, &(&1.group in [nil, ""])))
    |> assign(:group_legend, group_legend(selected_subjects))
    |> assign(:total_sessions, Enum.sum_by(per_subject, &length(&1.videos)))
    |> assign(:table_rows, table_rows(per_subject))
  end

  # Chronological (oldest-first) within each subject; subjects don't share a
  # timeline so grouping (not interleaving) is the only ordering that makes
  # sense here.
  defp table_rows(per_subject) do
    Enum.flat_map(per_subject, fn %{subject: s, videos: videos} ->
      videos |> Enum.reverse() |> Enum.map(&{s, &1})
    end)
  end

  # --- Trend view series ---

  defp subject_series(per_subject) do
    per_subject
    |> Enum.map(fn %{subject: s, points: points} ->
      %{label: s.name, color: subject_color(s.id), points: points}
    end)
    |> Enum.reject(&(&1.points == []))
  end

  # Group aggregate lines are visually distinguished from per-subject lines by
  # the muted `group_color/1` palette plus a "(mean)" suffix — SD is surfaced
  # in the per-point tooltip since `trend_chart/1` has no band primitive.
  defp group_series(per_group) do
    per_group
    |> Enum.map(fn %{group: g, points: points} ->
      %{label: "#{g} (mean)", color: group_color(g), points: Enum.map(points, &with_sd_label/1)}
    end)
    |> Enum.reject(&(&1.points == []))
  end

  defp with_sd_label(%{sd: nil} = p), do: p

  defp with_sd_label(%{sd: sd, n: n} = p),
    do: %{p | label: "#{p.label} (n=#{n}, ±#{Float.round(sd, 2)})"}

  # --- Box view categories ---

  # One box per selected subject, over that subject's per-session values,
  # colored by the subject's group.
  defp subject_categories(per_subject, metric) do
    per_subject
    |> Enum.map(fn %{subject: s, videos: videos} ->
      values = Reporting.metric_values(videos, metric)

      %{
        label: s.name,
        color: group_color(s.group),
        box: Reporting.boxplot_stats(values),
        points: Enum.map(values, &%{label: nil, value: &1})
      }
    end)
    |> Enum.reject(&(&1.box == nil))
  end

  # One box per subject built from the *per-frame* speed samples pooled across
  # that subject's sessions (`tracking_result.speed_samples`) — the true speed
  # distribution, not session-to-session means. Colored by group; no data dots
  # (thousands of frames) and no outlier markers, just the box + whiskers.
  # Subjects whose sessions predate speed-sample capture contribute nothing.
  defp speed_categories(per_subject) do
    per_subject
    |> Enum.map(fn %{subject: s, videos: videos} ->
      samples =
        videos
        |> Enum.map(& &1.tracking_result)
        |> Enum.reject(&is_nil/1)
        |> Enum.flat_map(&(&1.speed_samples || []))

      %{
        label: s.name,
        color: group_color(s.group),
        box: Reporting.boxplot_stats(samples),
        points: []
      }
    end)
    |> Enum.reject(&(&1.box == nil))
  end

  # One box per group; each dot is a (subject, experiment) pair (a subject's
  # mean within one experiment), named by subject. Subjects with no group are
  # excluded (surfaced via `@ungrouped_selected?`).
  defp group_categories(per_subject, metric) do
    per_subject
    |> Enum.flat_map(fn %{subject: s, videos: videos} ->
      case s.group do
        g when g in [nil, ""] ->
          []

        g ->
          videos
          |> Reporting.per_experiment_means(metric)
          |> Enum.map(fn %{experiment: e, value: v} ->
            {g, %{label: s.name, value: v, exp: e.name}}
          end)
      end
    end)
    |> Enum.group_by(fn {g, _dot} -> g end, fn {_g, dot} -> dot end)
    |> Enum.map(fn {g, dots} ->
      %{
        label: g,
        color: group_color(g),
        box: Reporting.boxplot_stats(Enum.map(dots, & &1.value)),
        points: dots
      }
    end)
    |> Enum.reject(&(&1.box == nil))
    |> Enum.sort_by(& &1.label)
  end

  # The distinct groups among the selected subjects, each with the swatch color
  # used to fill its boxes in the per-subject view — drives that view's legend.
  # `nil`/blank group is shown as "No group", sorted last.
  defp group_legend(selected_subjects) do
    selected_subjects
    |> Enum.map(& &1.group)
    |> Enum.uniq()
    |> Enum.sort_by(fn g -> {g in [nil, ""], g} end)
    |> Enum.map(fn g ->
      %{label: if(g in [nil, ""], do: "No group", else: g), color: group_color(g)}
    end)
  end

  # --- Selection parsing ---

  # `subjects` is a comma-separated list of ids in the URL (`?subjects=1,2`).
  # Absent (first visit) defaults to the first subject; present-but-empty (user
  # deselected everything) is honored as "nothing selected".
  defp selected_subjects(nil, subjects) do
    case subjects do
      [] -> []
      [first | _] -> [first]
    end
  end

  defp selected_subjects(str, subjects) do
    valid_ids = MapSet.new(subjects, & &1.id)

    ids =
      str
      |> String.split(",", trim: true)
      |> Enum.flat_map(fn s ->
        case Integer.parse(s) do
          {id, ""} -> if MapSet.member?(valid_ids, id), do: [id], else: []
          _ -> []
        end
      end)
      |> Enum.uniq()

    Enum.filter(subjects, &(&1.id in ids))
  end

  defp unselected_subjects(picker_subjects, selected_subjects) do
    selected_ids = MapSet.new(selected_subjects, & &1.id)
    Enum.reject(picker_subjects, &MapSet.member?(selected_ids, &1.id))
  end

  defp selected_groups(nil, _all_groups), do: []

  defp selected_groups(str, all_groups) do
    valid = MapSet.new(all_groups)
    str |> String.split(",", trim: true) |> Enum.filter(&MapSet.member?(valid, &1)) |> Enum.uniq()
  end

  defp unselected_groups(all_groups, selected_groups), do: all_groups -- selected_groups

  # --- Events ---

  @impl true
  def handle_event("set_experiment", %{"experiment" => experiment}, socket) do
    {:noreply, patch(socket, experiment: experiment)}
  end

  def handle_event("set_view", %{"view" => view}, socket) do
    {:noreply, patch(socket, view: view)}
  end

  def handle_event("select_metric", %{"metric" => metric}, socket) do
    {:noreply, patch(socket, metric: metric)}
  end

  def handle_event("toggle_log1p", _params, socket) do
    {:noreply, patch(socket, log1p: if(socket.assigns.log1p, do: nil, else: "1"))}
  end

  def handle_event("toggle_subject", %{"subject" => ""}, socket), do: {:noreply, socket}

  def handle_event("toggle_subject", %{"subject" => subject_id}, socket) do
    id = String.to_integer(subject_id)
    current_ids = Enum.map(socket.assigns.selected_subjects, & &1.id)

    new_ids =
      if id in current_ids, do: List.delete(current_ids, id), else: current_ids ++ [id]

    {:noreply, patch(socket, subjects: Enum.join(new_ids, ","))}
  end

  def handle_event("toggle_group", %{"group" => ""}, socket), do: {:noreply, socket}

  # Adding a group unions in every member subject (in the current experiment
  # scope); removing it subtracts that group's members, except ones still
  # covered by another selected group.
  def handle_event("toggle_group", %{"group" => group}, socket) do
    scope = socket.assigns.current_scope
    exp = socket.assigns.experiment_id
    current = socket.assigns.selected_groups
    selected_ids = Enum.map(socket.assigns.selected_subjects, & &1.id)

    {new_groups, new_ids} =
      if group in current do
        remaining = List.delete(current, group)
        removed = MapSet.new(member_ids(scope, group, exp))
        kept_by_others = other_group_member_ids(scope, remaining, exp)

        ids =
          Enum.filter(selected_ids, fn id ->
            not MapSet.member?(removed, id) or MapSet.member?(kept_by_others, id)
          end)

        {remaining, ids}
      else
        {current ++ [group], Enum.uniq(selected_ids ++ member_ids(scope, group, exp))}
      end

    {:noreply,
     patch(socket, groups: Enum.join(new_groups, ","), subjects: Enum.join(new_ids, ","))}
  end

  defp member_ids(scope, group, exp) do
    scope |> Reporting.experiment_group_members(group, exp) |> Enum.map(& &1.id)
  end

  defp other_group_member_ids(scope, groups, exp) do
    groups |> Enum.flat_map(&member_ids(scope, &1, exp)) |> MapSet.new()
  end

  defp patch(socket, overrides) do
    base = [
      experiment: socket.assigns.experiment_id || "all",
      view: socket.assigns.view,
      subjects: Enum.map_join(socket.assigns.selected_subjects, ",", &to_string(&1.id)),
      groups: Enum.join(socket.assigns.selected_groups, ","),
      metric: socket.assigns.metric,
      log1p: if(socket.assigns.log1p, do: "1", else: nil)
    ]

    params = patch_params(base, overrides)
    push_patch(socket, to: ~p"/analyses?#{params}")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={:analyses}
      breadcrumb="Analyses"
      page_title="Analyses"
    >
      <div class="mx-auto max-w-[1000px]">
        <h1 class="text-[23px] font-bold text-[#0f1729]">Analyses</h1>

        <p class="mt-1 text-[13px] text-[#667085]">
          Compare a tracked metric across subjects and treatment groups. Pick an experiment, add
          groups (which pull in their subjects) or individual subjects, then switch views.
        </p>

        <.empty_state
          :if={@subjects == []}
          class="mt-5"
          icon="hero-chart-bar"
          title="No subjects yet"
          subtitle="Charts appear here once you have tracked videos for at least one subject."
        />

        <div :if={@subjects != []} class="mt-5 space-y-3">
          <div class="flex flex-wrap items-center gap-2 rounded-[13px] border border-[#e7e9ee] bg-white p-2">
            <span class="px-2 text-[11px] font-semibold uppercase tracking-wide text-[#98a2b3]">
              Experiment
            </span>

            <form id="analyses-experiment" phx-change="set_experiment">
              <select
                name="experiment"
                class="rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-1.5 text-[12.5px] font-medium text-[#0f1729] focus:border-[#CC5500] focus:outline-none"
              >
                <option value="all" selected={@experiment_id == nil}>All experiments</option>
                <option :for={e <- @experiments} value={e.id} selected={@experiment_id == e.id}>
                  {e.name}
                </option>
              </select>
            </form>
          </div>

          <div
            :if={@groups != []}
            class="flex flex-wrap items-center gap-2 rounded-[13px] border border-[#e7e9ee] bg-white p-2"
          >
            <span class="px-2 text-[11px] font-semibold uppercase tracking-wide text-[#98a2b3]">
              Groups
            </span>

            <form
              :if={unselected_groups(@groups, @selected_groups) != []}
              id="analyses-group-picker"
              phx-change="toggle_group"
            >
              <select
                name="group"
                class="rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-1.5 text-[12.5px] font-medium text-[#667085] focus:border-[#CC5500] focus:outline-none"
              >
                <option value="" selected>+ Add group…</option>
                <option :for={g <- unselected_groups(@groups, @selected_groups)} value={g}>
                  {g}
                </option>
              </select>
            </form>

            <button
              :for={g <- @selected_groups}
              type="button"
              phx-click="toggle_group"
              phx-value-group={g}
              class="inline-flex items-center gap-2 rounded-[8px] bg-[#0f1729] px-3 py-1.5 text-[12.5px] font-medium text-white transition-colors hover:bg-[#1e293f]"
            >
              <span class="size-2 rounded-full" style={"background:#{group_color(g)}"}></span>
              <span class="font-data">{g}</span>
              <.icon name="hero-x-mark-micro" class="size-3.5 text-white/70" />
            </button>
          </div>

          <div class="flex flex-wrap items-center gap-2 rounded-[13px] border border-[#e7e9ee] bg-white p-2">
            <span class="px-2 text-[11px] font-semibold uppercase tracking-wide text-[#98a2b3]">
              Subjects
            </span>

            <form
              :if={unselected_subjects(@picker_subjects, @selected_subjects) != []}
              id="analyses-subject-picker"
              phx-change="toggle_subject"
            >
              <select
                name="subject"
                class="rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-1.5 text-[12.5px] font-medium text-[#667085] focus:border-[#CC5500] focus:outline-none"
              >
                <option value="" selected>+ Add subject…</option>
                <option
                  :for={s <- unselected_subjects(@picker_subjects, @selected_subjects)}
                  value={s.id}
                >
                  {s.name}
                </option>
              </select>
            </form>

            <button
              :for={s <- @selected_subjects}
              type="button"
              phx-click="toggle_subject"
              phx-value-subject={s.id}
              class="inline-flex items-center gap-2 rounded-[8px] bg-[#0f1729] px-3 py-1.5 text-[12.5px] font-medium text-white transition-colors hover:bg-[#1e293f]"
            >
              <span class="size-2 rounded-full" style={"background:#{subject_color(s.id)}"}></span>
              <span class="font-data">{s.name}</span>
              <.icon name="hero-x-mark-micro" class="size-3.5 text-white/70" />
            </button>
          </div>
        </div>

        <.empty_state
          :if={@subjects != [] and @selected_subjects == [] and @selected_groups == []}
          class="mt-4"
          title="No subject or group selected"
          subtitle="Pick an experiment and add a group or subject above to see its charts."
        />

        <div :if={@selected_subjects != [] or @selected_groups != []} class="mt-4">
          <div class="flex flex-wrap items-center justify-between gap-3 rounded-[13px] border border-[#e7e9ee] bg-white p-3">
            <div class="text-[12.5px] text-[#667085]">
              <span class="font-data font-semibold text-[#0f1729]">{@total_sessions}</span>
              analyzed session(s) across
              <span class="font-data font-semibold text-[#0f1729]">
                {length(@selected_subjects)}
              </span>
              subject(s)
            </div>

            <div class="inline-flex flex-wrap items-center gap-1 rounded-[9px] border border-[#e7e9ee] bg-white p-1">
              <button
                :for={{key, label} <- views()}
                type="button"
                phx-click="set_view"
                phx-value-view={key}
                class={[
                  "rounded-[6px] px-3 py-1.5 text-[12.5px] font-medium transition-colors",
                  @view == key && "bg-[#0f1729] text-white",
                  @view != key && "text-[#667085] hover:text-[#0f1729]"
                ]}
              >
                {label}
              </button>
            </div>
          </div>

          <div class="mt-3 flex flex-wrap items-center gap-3">
            <div
              :if={@view != "speed_box"}
              class="inline-flex flex-wrap items-center gap-1 rounded-[9px] border border-[#e7e9ee] bg-white p-1"
            >
              <button
                :for={{key, label, _unit} <- metrics()}
                type="button"
                phx-click="select_metric"
                phx-value-metric={key}
                class={[
                  "rounded-[6px] px-3 py-1.5 text-[12.5px] font-medium transition-colors",
                  @metric == key && "bg-[#0f1729] text-white",
                  @metric != key && "text-[#667085] hover:text-[#0f1729]"
                ]}
              >
                {label}
              </button>
            </div>

            <button
              :if={@view != "trend"}
              type="button"
              phx-click="toggle_log1p"
              class={[
                "rounded-[8px] border px-3 py-1.5 text-[12.5px] font-medium transition-colors",
                @log1p && "border-[#CC5500] bg-[#fbeee4] text-[#b34a00]",
                !@log1p && "border-[#e7e9ee] bg-white text-[#667085] hover:text-[#0f1729]"
              ]}
            >
              log1p {if @log1p, do: "on", else: "off"}
            </button>

            <button
              :if={chart_present?(assigns)}
              id="analyses-export"
              type="button"
              phx-hook="ChartExport"
              data-capture="analyses-chart-card"
              data-name={export_name(@view, @metric)}
              class="ml-auto inline-flex items-center gap-1.5 rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-1.5 text-[12.5px] font-medium text-[#667085] transition-colors hover:text-[#0f1729] disabled:opacity-60"
            >
              <.icon name="hero-arrow-down-tray" class="size-3.5" />
              <span data-label>Export PNG</span>
            </button>
          </div>

          <div
            id="analyses-chart-card"
            class="mt-3 rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]"
          >
            <div class="text-[13px] font-bold text-[#0f1729]">
              {chart_title(@view, @metric)}
            </div>

            <div :if={@view == "trend"} class="mt-4">
              <.trend_chart
                :if={@trend_series != []}
                id="analyses-trend-chart"
                series={@trend_series}
                unit={metric_unit(@metric)}
              />
              <p
                :if={length(@selected_subjects) == 1 and match?([%{points: [_]}], @trend_series)}
                class="mt-2 text-[11.5px] text-[#8a93a3]"
              >
                Only one session so far — add more to see a trend.
              </p>
              <.chart_empty :if={@trend_series == []} />
            </div>

            <div :if={@view == "subject_box"} class="mt-4">
              <.box_plot
                :if={@subject_categories != []}
                id="analyses-subject-box"
                categories={@subject_categories}
                unit={metric_unit(@metric)}
                log1p={@log1p}
              />
              <.chart_empty :if={@subject_categories == []} />
            </div>

            <div :if={@view == "group_box"} class="mt-4">
              <.box_plot
                :if={@group_categories != []}
                id="analyses-group-box"
                categories={@group_categories}
                unit={metric_unit(@metric)}
                log1p={@log1p}
                jitter={false}
              />
              <.chart_empty
                :if={@group_categories == []}
                message="No group data for this metric. Assign groups to the selected subjects."
              />
              <p
                :if={@group_categories != [] and @ungrouped_selected?}
                class="mt-2 text-[11.5px] text-[#8a93a3]"
              >
                Subjects without a group are not shown here.
              </p>
            </div>

            <div :if={@view == "speed_box"} class="mt-4">
              <.box_plot
                :if={@speed_categories != []}
                id="analyses-speed-box"
                categories={@speed_categories}
                unit="cm/s"
                log1p={@log1p}
                show_outliers={false}
              />
              <.chart_empty
                :if={@speed_categories == []}
                message="No per-frame speed data for the selected subjects yet — re-process their videos to populate the speed distribution."
              />
            </div>

            <div
              :if={@view != "trend"}
              class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2 text-[11px] text-[#667085]"
            >
              <span class="inline-flex items-center gap-1.5">
                <svg width="20" height="6" viewBox="0 0 20 6" aria-hidden="true">
                  <line x1="0" y1="3" x2="20" y2="3" stroke="#0f1729" stroke-width="2" />
                </svg>
                Median
              </span>
              <span class="inline-flex items-center gap-1.5">
                <svg width="20" height="6" viewBox="0 0 20 6" aria-hidden="true">
                  <line
                    x1="0"
                    y1="3"
                    x2="20"
                    y2="3"
                    stroke="#0f1729"
                    stroke-width="1.5"
                    stroke-dasharray="3 2"
                  />
                </svg>
                Mean
              </span>
              <span class="text-[#98a2b3]">· whiskers at 1.5·IQR</span>

              <span :if={@view == "group_box"} class="text-[#98a2b3]">
                · hover a point for its subject
              </span>

              <span
                :if={@view in ["subject_box", "speed_box"] and @group_legend != []}
                class="ml-auto inline-flex flex-wrap items-center gap-x-3 gap-y-1"
              >
                <span class="text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
                  Groups
                </span>
                <span :for={g <- @group_legend} class="inline-flex items-center gap-1.5">
                  <span class="size-2.5 rounded-[3px]" style={"background:#{g.color}"}></span>
                  {g.label}
                </span>
              </span>
            </div>
          </div>

          <div
            :if={@table_rows != []}
            class="mt-4 overflow-x-auto rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]"
          >
            <table class="w-full min-w-[860px] text-left text-[12.5px]">
              <thead>
                <tr class="border-b border-[#f4f5f7] text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
                  <th class="pb-2">Subject</th>
                  <th class="pb-2">Date</th>
                  <th class="pb-2">Experiment</th>
                  <th class="pb-2">Video</th>
                  <th class="pb-2">Distance</th>
                  <th class="pb-2">Mean speed</th>
                  <th class="pb-2">Thigmotaxis</th>
                  <th class="pb-2">Tortuosity</th>
                  <th class="pb-2">Immobility</th>
                </tr>
              </thead>

              <tbody>
                <tr :for={{s, v} <- @table_rows} class="border-b border-[#f4f5f7] last:border-0">
                  <td class="py-2.5">
                    <span class="inline-flex items-center gap-2">
                      <span class="size-2 rounded-full" style={"background:#{subject_color(s.id)}"}></span>
                      <span class="font-data text-[#0f1729]">{s.name}</span>
                    </span>
                  </td>
                  <td class="py-2.5 font-data text-[#344054]">
                    {Calendar.strftime(v.inserted_at, "%Y-%m-%d")}
                  </td>
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
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </Layouts.locomo>
    """
  end

  attr :message, :string, default: "No analyzed sessions have a value for this metric yet."

  defp chart_empty(assigns) do
    ~H"""
    <div class="mt-2 flex flex-col items-center rounded-[10px] border border-dashed border-[#d4d8df] py-10 text-center">
      <p class="text-[13px] text-[#667085]">{@message}</p>
    </div>
    """
  end

  # --- helpers ---

  defp metrics, do: @metrics

  defp views,
    do: [
      {"trend", "Trend"},
      {"subject_box", "Per subject"},
      {"group_box", "Per group"},
      {"speed_box", "Speed dist."}
    ]

  defp metric_label(key), do: metrics() |> Enum.find(&(elem(&1, 0) == key)) |> elem(1)
  defp metric_unit(key), do: metrics() |> Enum.find(&(elem(&1, 0) == key)) |> elem(2)

  defp view_suffix("trend"), do: "over time"
  defp view_suffix("subject_box"), do: "by subject"
  defp view_suffix("group_box"), do: "by group"
  defp view_suffix("speed_box"), do: "by subject"

  # The metric selector is hidden on the speed view (it's always speed), so its
  # title is fixed rather than derived from the selected metric.
  defp chart_title("speed_box", _metric), do: "Speed distribution by subject"
  defp chart_title(view, metric), do: "#{metric_label(metric)} #{view_suffix(view)}"

  # Whether the current view actually has a chart rendered (so the Export button
  # only appears when there's something to capture).
  defp chart_present?(%{view: "trend", trend_series: series}), do: series != []
  defp chart_present?(%{view: "subject_box", subject_categories: cats}), do: cats != []
  defp chart_present?(%{view: "group_box", group_categories: cats}), do: cats != []
  defp chart_present?(%{view: "speed_box", speed_categories: cats}), do: cats != []

  defp export_name("speed_box", _metric), do: "analyses-speed-distribution"
  defp export_name(view, metric), do: "analyses-#{String.replace(view, "_", "-")}-#{metric}"
end
