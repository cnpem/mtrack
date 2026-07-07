defmodule MouseTrackerWeb.ExperimentLive.Index do
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments

  @tabs [{"all", "All"}, {"done", "Done"}, {"processing", "Processing"}, {"pending", "Pending"}]

  @impl true
  def mount(_params, _session, socket) do
    experiments = Experiments.list_experiments_with_details(socket.assigns.current_scope)

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
          <.link
            navigate={~p"/experiments/new"}
            class="inline-flex items-center gap-1.5 rounded-[8px] bg-[#CC5500] px-3.5 py-2.5 text-[13px] font-semibold text-white shadow-[0_1px_2px_rgba(204,85,0,.3)] hover:bg-[#b34a00]"
          >
            <.icon name="hero-plus-micro" class="size-4" /> New Experiment
          </.link>
        </div>

        <div class="mt-5 flex flex-wrap items-center justify-between gap-3">
          <form phx-change="search" class="relative w-full max-w-[320px]">
            <.icon
              name="hero-magnifying-glass-micro"
              class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[#98a2b3]"
            />
            <input
              type="text"
              name="query"
              value={@query}
              phx-debounce="200"
              placeholder="Search by name or subject"
              autocomplete="off"
              class="w-full rounded-[8px] border border-[#e7e9ee] bg-white py-2 pl-9 pr-3 text-[13px] text-[#0f1729] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none"
            />
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

        <div :if={@experiments == []} class="mt-6">
          <.empty_state active_filter={@query != "" or @status_filter != "all"} />
        </div>

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

  attr :active_filter, :boolean, required: true

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center rounded-[13px] border border-dashed border-[#d4d8df] bg-white px-6 py-16 text-center">
      <div class="flex size-12 items-center justify-center rounded-full bg-[#f2f4f7] text-[#98a2b3]">
        <.icon name="hero-beaker" class="size-6" />
      </div>
      <h2 class="mt-4 text-[15px] font-bold text-[#0f1729]">
        {if @active_filter, do: "No matching experiments", else: "No experiments yet"}
      </h2>
      <p class="mt-1 max-w-sm text-[13px] text-[#667085]">
        {if @active_filter,
          do: "Try a different search or status filter.",
          else: "Upload locomotion videos to run the tracking pipeline and review metrics."}
      </p>
      <.link
        :if={!@active_filter}
        navigate={~p"/experiments/new"}
        class="mt-5 inline-flex items-center gap-1.5 rounded-[8px] bg-[#CC5500] px-3.5 py-2.5 text-[13px] font-semibold text-white hover:bg-[#b34a00]"
      >
        <.icon name="hero-plus-micro" class="size-4" /> Create your first experiment
      </.link>
    </div>
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
