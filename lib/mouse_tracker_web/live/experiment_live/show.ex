defmodule MouseTrackerWeb.ExperimentLive.Show do
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    experiment = Experiments.get_experiment_with_details!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, experiment.name)
     |> assign(:experiment, experiment)
     |> assign(:experiment_subjects, Experiments.experiment_subjects(experiment))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={:experiments}
      breadcrumb="Experiments"
      page_title={@experiment.name}
    >
      <div class="mx-auto max-w-[1000px]">
        <.link
          navigate={~p"/experiments"}
          class="inline-flex items-center gap-1 text-[12.5px] text-[#667085] hover:text-[#0f1729]"
        >
          <.icon name="hero-chevron-left-micro" class="size-4" /> Experiments
        </.link>

        <div class="mt-3 flex items-start justify-between gap-4">
          <div>
            <div class="flex items-center gap-3">
              <h1 class="text-[23px] font-bold text-[#0f1729]">{@experiment.name}</h1>
              <.status_pill status={Experiments.experiment_status(@experiment)} />
            </div>
            <p :if={@experiment.description} class="mt-1.5 max-w-2xl text-[13px] text-[#667085]">
              {@experiment.description}
            </p>
          </div>
        </div>

        <div class="mt-5 grid grid-cols-2 divide-x divide-[#e7e9ee] overflow-hidden rounded-[13px] border border-[#e7e9ee] bg-white sm:grid-cols-4">
          <.meta_cell label="Videos" value={to_string(length(@experiment.videos))} />
          <.meta_cell label="Subjects" value={to_string(length(@experiment_subjects))} />
          <.meta_cell label="Analyzed" value={to_string(analyzed_count(@experiment))} />
          <.meta_cell label="Created" value={format_date(@experiment.inserted_at)} />
        </div>

        <div :if={@experiment_subjects != []} class="mt-5 flex flex-wrap gap-2">
          <div
            :for={subject <- @experiment_subjects}
            class="inline-flex items-center gap-2 rounded-[20px] border border-[#e7e9ee] bg-white px-3 py-1.5"
          >
            <span class="size-2 rounded-full" style={"background:#{subject_color(subject.id)}"}></span>
            <span class="font-data text-[12px] font-medium text-[#344054]">{subject.name}</span>
            <span :if={subject.genotype} class="text-[11px] text-[#98a2b3]">{subject.genotype}</span>
          </div>
        </div>

        <div class="mt-7 flex items-center justify-between">
          <h2 class="text-[15px] font-bold text-[#0f1729]">
            Videos
            <span class="ml-1 font-normal text-[#98a2b3]">
              {analyzed_count(@experiment)}/{length(@experiment.videos)} analyzed
            </span>
          </h2>
        </div>

        <div
          :if={@experiment.videos == []}
          class="mt-3 rounded-[13px] border border-dashed border-[#d4d8df] bg-white px-6 py-12 text-center text-[13px] text-[#667085]"
        >
          No videos in this experiment yet.
        </div>

        <ul class="mt-3 space-y-2.5">
          <li
            :for={video <- @experiment.videos}
            class="flex items-center gap-4 rounded-[13px] border border-[#e7e9ee] bg-white p-[16px] shadow-[0_1px_2px_rgba(16,24,40,.04)]"
          >
            <div class="flex size-12 shrink-0 items-center justify-center rounded-[10px] bg-[#11161f] text-white/80">
              <.icon name="hero-play-solid" class="size-5" />
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span
                  :if={video.subject}
                  class="size-2 rounded-full"
                  style={"background:#{subject_color(video.subject_id)}"}
                ></span>
                <span class="truncate font-data text-[13px] font-medium text-[#0f1729]">
                  {video.filename}
                </span>
              </div>
              <div class="mt-0.5 truncate text-[11.5px] text-[#8a93a3]">
                {video_meta_line(video)}
              </div>
            </div>
            <.status_pill status={video.status} />
            <.video_action experiment={@experiment} video={video} />
          </li>
        </ul>

        <div class="mt-6 rounded-[13px] border border-dashed border-[#d4d8df] bg-white px-6 py-8 text-center">
          <p class="text-[13px] font-medium text-[#667085]">Add more videos to this experiment</p>
          <p class="mt-1 text-[11.5px] text-[#98a2b3]">
            Uploading into an existing experiment is coming with the upload wizard.
          </p>
        </div>
      </div>
    </Layouts.locomo>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp meta_cell(assigns) do
    ~H"""
    <div class="px-4 py-3.5">
      <div class="text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">{@label}</div>
      <div class="mt-1 font-data text-[14px] font-medium text-[#0f1729]">{@value}</div>
    </div>
    """
  end

  attr :experiment, :map, required: true
  attr :video, :map, required: true

  defp video_action(%{video: %{status: "done"}} = assigns) do
    ~H"""
    <.link
      navigate={~p"/experiments/#{@experiment.id}/results?#{[video: @video.id]}"}
      class="rounded-[8px] bg-[#CC5500] px-3 py-2 text-[12.5px] font-semibold text-white hover:bg-[#b34a00]"
    >
      View results
    </.link>
    """
  end

  defp video_action(%{video: %{status: "processing"}} = assigns) do
    ~H"""
    <.link
      navigate={~p"/videos/#{@video.id}/processing"}
      class="rounded-[8px] border border-[#e7e9ee] px-3 py-2 text-[12.5px] font-semibold text-[#344054] hover:border-[#d4d8df]"
    >
      View progress
    </.link>
    """
  end

  defp video_action(%{video: %{status: "error"}} = assigns) do
    ~H"""
    <.link
      navigate={~p"/videos/#{@video.id}/processing"}
      class="rounded-[8px] border border-[#fca5a5] px-3 py-2 text-[12.5px] font-semibold text-[#b42318] hover:bg-[#fdecec]"
    >
      View error
    </.link>
    """
  end

  defp video_action(assigns) do
    ~H"""
    <span class="px-3 py-2 text-[12.5px] font-medium text-[#98a2b3]">Queued</span>
    """
  end

  defp analyzed_count(experiment) do
    Enum.count(experiment.videos, &(&1.status == "done"))
  end

  defp video_meta_line(video) do
    [
      video.subject && video.subject.name,
      video.fps && "#{video.fps} fps",
      video.duration_seconds && "#{round(video.duration_seconds)}s"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> case do
      [] -> "No metadata yet"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
end
