defmodule MouseTrackerWeb.ComingSoonLive do
  @moduledoc """
  Placeholder inside the Locomo shell for screens not yet built (upload wizard,
  results, datasets, analyses, pipeline settings). Keeps navigation coherent so
  no link 404s while those parts are implemented.
  """
  use MouseTrackerWeb, :live_view

  @screens %{
    new: {:experiments, "New experiment", "The upload wizard is the next part to be built."},
    results:
      {:experiments, "Results", "The 3-tab results dashboard is coming in a following part."},
    datasets: {:datasets, "Datasets", "The dataset library is planned for a later iteration."},
    analyses:
      {:analyses, "Analyses", "The trajectory-replay tool is planned for a later iteration."},
    settings:
      {:settings, "Pipeline settings",
       "Global pipeline defaults are planned for a later iteration."}
  }

  @impl true
  def mount(_params, _session, socket) do
    {active, title, body} = Map.fetch!(@screens, socket.assigns.live_action)

    {:ok,
     socket
     |> assign(:page_title, title)
     |> assign(:active, active)
     |> assign(:title, title)
     |> assign(:body, body)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={@active}
      breadcrumb="Locomo"
      page_title={@title}
    >
      <div class="mx-auto max-w-[720px]">
        <div class="flex flex-col items-center rounded-[13px] border border-dashed border-[#d4d8df] bg-white px-6 py-20 text-center">
          <div class="flex size-12 items-center justify-center rounded-full bg-[#fbeee4] text-[#CC5500]">
            <.icon name="hero-wrench-screwdriver" class="size-6" />
          </div>
          <h1 class="mt-4 text-[18px] font-bold text-[#0f1729]">{@title}</h1>
          <p class="mt-1.5 max-w-md text-[13px] text-[#667085]">{@body}</p>
          <.link
            navigate={~p"/experiments"}
            class="mt-6 inline-flex items-center gap-1.5 rounded-[8px] border border-[#e7e9ee] px-3.5 py-2.5 text-[13px] font-semibold text-[#344054] hover:border-[#d4d8df]"
          >
            <.icon name="hero-arrow-left-micro" class="size-4" /> Back to experiments
          </.link>
        </div>
      </div>
    </Layouts.locomo>
    """
  end
end
