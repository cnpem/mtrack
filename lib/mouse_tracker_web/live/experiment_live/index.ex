defmodule MouseTrackerWeb.ExperimentLive.Index do
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments
  alias MouseTrackerWeb.VideoStatusSync

  @tabs [{"all", "All"}, {"done", "Done"}, {"processing", "Processing"}, {"pending", "Pending"}]

  @impl true
  def mount(_params, _session, socket) do
    experiments = Experiments.list_experiments_with_details(socket.assigns.current_scope)

    if connected?(socket) do
      VideoStatusSync.subscribe_all(Enum.flat_map(experiments, & &1.videos))
    end

    {:ok,
     socket
     |> assign(:page_title, "Experiments")
     |> assign(:query, "")
     |> assign(:status_filter, "all")
     |> assign(:all_experiments, experiments)
     |> assign_filtered()}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(:query, query) |> assign_filtered()}
  end

  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, socket |> assign(:status_filter, status) |> assign_filtered()}
  end

  @impl true
  def handle_info({:status, video_id, status}, socket) do
    experiments =
      Enum.map(socket.assigns.all_experiments, fn exp ->
        %{exp | videos: Enum.map(exp.videos, &VideoStatusSync.patch_status(&1, video_id, status))}
      end)

    {:noreply, socket |> assign(:all_experiments, experiments) |> assign_filtered()}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp assign_filtered(socket) do
    %{all_experiments: experiments, query: query, status_filter: status} = socket.assigns
    q = query |> String.trim() |> String.downcase()

    filtered =
      experiments
      |> Enum.filter(fn exp ->
        status == "all" or Experiments.experiment_status(exp) == status
      end)
      |> Enum.filter(fn exp -> q == "" or matches_query?(exp, q) end)

    assign(socket, :experiments, filtered)
  end

  defp matches_query?(exp, q) do
    names = [exp.name | Enum.map(Experiments.experiment_subjects(exp), & &1.name)]
    Enum.any?(names, fn name -> name && String.contains?(String.downcase(name), q) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={:experiments}
      breadcrumb="Workspace"
      page_title="Experiments"
    >
      <div class="mx-auto max-w-[1100px]">
        <div class="flex items-start justify-between">
          <div>
            <h1 class="text-[24px] font-bold text-[#0f1729]">Experiments</h1>
            <p class="mt-1 text-[13px] text-[#667085]">
              {length(@all_experiments)} {ngettext(
                "experiment",
                "experiments",
                length(@all_experiments)
              )} in this workspace
            </p>
          </div>
          <.button size="lg" shadow navigate={~p"/experiments/new"}>
            <.icon name="hero-plus-micro" class="size-4" /> New Experiment
          </.button>
        </div>

        <div class="mt-5 flex flex-wrap items-center justify-between gap-3">
          <.search_input query={@query} placeholder="Search by name or subject" />

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

        <.empty_state
          :if={@experiments == []}
          class="mt-6"
          icon="hero-beaker"
          title={
            if @query != "" or @status_filter != "all",
              do: "No matching experiments",
              else: "No experiments yet"
          }
          subtitle={
            if @query != "" or @status_filter != "all",
              do: "Try a different search or status filter.",
              else: "Upload locomotion videos to run the tracking pipeline and review metrics."
          }
        >
          <.button
            :if={@query == "" and @status_filter == "all"}
            size="lg"
            class="mt-5"
            navigate={~p"/experiments/new"}
          >
            <.icon name="hero-plus-micro" class="size-4" /> Create your first experiment
          </.button>
        </.empty_state>

        <ul :if={@experiments != []} class="mt-4 space-y-2.5">
          <li :for={exp <- @experiments}>
            <.link
              navigate={~p"/experiments/#{exp.id}"}
              class="group flex items-center gap-4 rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)] transition-all hover:-translate-y-px hover:border-[#d4d8df] hover:shadow-[0_4px_14px_rgba(16,24,40,.07)]"
            >
              <.icon_tile icon="hero-beaker" />
              <div class="min-w-0 flex-1">
                <div class="truncate text-[15px] font-bold text-[#0f1729]">{exp.name}</div>
                <div class="mt-0.5 truncate font-data text-[12px] text-[#8a93a3]">
                  {subjects_line(exp)}
                </div>
              </div>
              <div class="hidden w-24 text-center sm:block">
                <div class="font-data text-[14px] font-medium text-[#344054]">
                  {length(exp.videos)}
                </div>
                <div class="text-[10.5px] text-[#98a2b3]">videos</div>
              </div>
              <div class="hidden w-28 text-right md:block">
                <div class="font-data text-[12px] text-[#667085]">{format_date(exp.inserted_at)}</div>
                <div class="text-[10.5px] text-[#98a2b3]">created</div>
              </div>
              <.status_pill status={Experiments.experiment_status(exp)} />
              <.icon
                name="hero-chevron-right-mini"
                class="size-4 text-[#b0b7c1] group-hover:text-[#667085]"
              />
            </.link>
          </li>
        </ul>
      </div>
    </Layouts.locomo>
    """
  end

  defp tabs, do: @tabs

  defp subjects_line(exp) do
    case Experiments.experiment_subjects(exp) do
      [] -> "No subjects"
      subjects -> subjects |> Enum.map(& &1.name) |> Enum.join(" · ")
    end
  end

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
end
