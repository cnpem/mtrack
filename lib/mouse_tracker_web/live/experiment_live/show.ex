defmodule MouseTrackerWeb.ExperimentLive.Show do
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments
  alias MouseTracker.Experiments.Subjects
  alias MouseTrackerWeb.VideoStatusSync

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    experiment = Experiments.get_experiment_with_details!(socket.assigns.current_scope, id)

    if connected?(socket) do
      VideoStatusSync.subscribe_all(experiment.videos)
    end

    {:ok,
     socket
     |> assign(:page_title, experiment.name)
     |> assign(:experiment, experiment)
     |> assign(:experiment_subjects, Experiments.experiment_subjects(experiment))
     |> assign(:export_open, false)
     |> assign(:export_opts, %{
       date: true,
       video: true,
       calibration: true,
       heatmap: false,
       speed: false
     })}
  end

  @impl true
  def handle_event("update_subject_notes", %{"subject-id" => id, "value" => notes}, socket) do
    subject = Subjects.get_subject!(socket.assigns.current_scope, id)

    {:ok, updated} =
      Subjects.update_subject(socket.assigns.current_scope, subject, %{notes: notes})

    {:noreply,
     update(socket, :experiment_subjects, fn subjects ->
       Enum.map(subjects, &if(&1.id == updated.id, do: updated, else: &1))
     end)}
  end

  def handle_event("toggle_export", _params, socket) do
    {:noreply, update(socket, :export_open, &(!&1))}
  end

  def handle_event("close_export", _params, socket) do
    {:noreply, assign(socket, :export_open, false)}
  end

  def handle_event("export_change", params, socket) do
    opts = %{
      date: Map.has_key?(params, "date"),
      video: Map.has_key?(params, "video"),
      calibration: Map.has_key?(params, "calibration"),
      heatmap: Map.has_key?(params, "heatmap"),
      speed: Map.has_key?(params, "speed")
    }

    {:noreply, assign(socket, :export_opts, opts)}
  end

  @impl true
  def handle_info({:status, video_id, status}, socket) do
    {:noreply,
     update(socket, :experiment, fn exp ->
       %{exp | videos: Enum.map(exp.videos, &VideoStatusSync.patch_status(&1, video_id, status))}
     end)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

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
          <div class="relative shrink-0" phx-click-away={@export_open && "close_export"}>
            <.button size="sm" type="button" phx-click="toggle_export">
              <.icon name="hero-arrow-down-tray-micro" class="size-4" /> Exportar
            </.button>

            <div
              :if={@export_open}
              class="absolute right-0 z-20 mt-2 w-72 rounded-[12px] border border-[#e7e9ee] bg-white p-4 text-left shadow-[0_8px_24px_rgba(16,24,40,.12)]"
            >
              <div class="text-[13px] font-bold text-[#0f1729]">Exportar dados</div>
              <p class="mt-0.5 text-[11.5px] text-[#8a93a3]">
                Cobaia e métricas sempre incluídas. Marcar imagens gera um .zip.
              </p>

              <form phx-change="export_change" class="mt-3 space-y-2">
                <label class="flex items-center gap-2 text-[12.5px] text-[#344054]">
                  <input
                    type="checkbox"
                    name="date"
                    checked={@export_opts.date}
                    class="size-4 rounded border-[#d4d8df] text-[#CC5500] focus:ring-[#CC5500]"
                  /> Data (experimento/vídeo)
                </label>
                <label class="flex items-center gap-2 text-[12.5px] text-[#344054]">
                  <input
                    type="checkbox"
                    name="video"
                    checked={@export_opts.video}
                    class="size-4 rounded border-[#d4d8df] text-[#CC5500] focus:ring-[#CC5500]"
                  /> Metadados do vídeo
                </label>
                <label class="flex items-center gap-2 text-[12.5px] text-[#344054]">
                  <input
                    type="checkbox"
                    name="calibration"
                    checked={@export_opts.calibration}
                    class="size-4 rounded border-[#d4d8df] text-[#CC5500] focus:ring-[#CC5500]"
                  /> Parâmetros de calibração
                </label>

                <div class="!mt-3 border-t border-[#f0f1f4] pt-2 text-[10.5px] font-semibold uppercase tracking-wide text-[#98a2b3]">
                  Imagens (zip)
                </div>
                <label class="flex items-center gap-2 text-[12.5px] text-[#344054]">
                  <input
                    type="checkbox"
                    name="heatmap"
                    checked={@export_opts.heatmap}
                    class="size-4 rounded border-[#d4d8df] text-[#CC5500] focus:ring-[#CC5500]"
                  /> Mapa de calor
                </label>
                <label class="flex items-center gap-2 text-[12.5px] text-[#344054]">
                  <input
                    type="checkbox"
                    name="speed"
                    checked={@export_opts.speed}
                    class="size-4 rounded border-[#d4d8df] text-[#CC5500] focus:ring-[#CC5500]"
                  /> Gráfico de velocidade
                </label>
              </form>

              <div class="mt-4 flex flex-col gap-2">
                <.button
                  size="sm"
                  href={
                    ~p"/experiments/#{@experiment.id}/export?#{export_query(@export_opts, "csv")}"
                  }
                  download
                >
                  <.icon name="hero-arrow-down-tray-micro" class="size-4" /> Baixar CSV
                </.button>
                <.button
                  size="sm"
                  variant="secondary"
                  href={
                    ~p"/experiments/#{@experiment.id}/export?#{export_query(@export_opts, "xlsx")}"
                  }
                  download
                >
                  <.icon name="hero-arrow-down-tray-micro" class="size-4" /> Baixar XLSX
                </.button>
              </div>
            </div>
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
            class="flex w-56 flex-col gap-1.5 rounded-[13px] border border-[#e7e9ee] bg-white p-3"
          >
            <div class="flex items-center gap-2">
              <span class="size-2 rounded-full" style={"background:#{subject_color(subject.id)}"}></span>
              <span class="font-data text-[12px] font-medium text-[#344054]">{subject.name}</span>
              <span :if={subject.genotype} class="text-[11px] text-[#98a2b3]">{subject.genotype}</span>
              <span :if={subject.group} class="text-[11px] text-[#98a2b3]">
                <span :if={subject.genotype}> · </span>{subject.group}
              </span>
            </div>
            <textarea
              name="notes"
              phx-blur="update_subject_notes"
              phx-value-subject-id={subject.id}
              rows="2"
              placeholder="Notes (e.g. limping, vision issue)"
              class="w-full resize-none rounded-[6px] border border-[#e7e9ee] bg-[#fafbfc] px-2 py-1.5 font-data text-[11.5px] text-[#344054] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none"
            >{subject.notes}</textarea>
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
              <div :if={video.rois != []} class="mt-1.5 flex flex-wrap gap-1">
                <.link
                  :for={roi <- video.rois}
                  navigate={~p"/videos/#{video.id}/rois/#{roi.id}/edit"}
                  class="inline-flex items-center gap-1 rounded-[6px] bg-[#f2f4f7] px-2 py-0.5 font-data text-[10.5px] text-[#475467] hover:bg-[#e7e9ee]"
                >
                  {roi.name} <.icon name="hero-pencil-square-micro" class="size-3" />
                </.link>
              </div>
            </div>
            <.status_pill status={video.status} />
            <.video_action experiment={@experiment} video={video} />
          </li>
        </ul>
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
    <.button
      size="sm"
      navigate={~p"/experiments/#{@experiment.id}/results?#{[video: @video.id]}"}
    >
      View results
    </.button>
    """
  end

  defp video_action(%{video: %{status: "processing"}} = assigns) do
    ~H"""
    <.button variant="secondary" size="sm" navigate={~p"/videos/#{@video.id}/processing"}>
      View progress
    </.button>
    """
  end

  defp video_action(%{video: %{status: "error"}} = assigns) do
    ~H"""
    <.button variant="danger" size="sm" navigate={~p"/videos/#{@video.id}/processing"}>
      View error
    </.button>
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
      video.subject && subject_label(video.subject),
      video.fps && "#{video.fps} fps",
      video.duration_seconds && "#{round(video.duration_seconds)}s"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> case do
      [] -> "No metadata yet"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp subject_label(%{name: name, group: group}) when is_binary(group) and group != "",
    do: "#{name} (#{group})"

  defp subject_label(%{name: name}), do: name

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")

  # Builds the query string for the export download link from the current panel
  # state, so the `<.link download>` href always reflects the checkboxes.
  defp export_query(opts, format) do
    [
      format: format,
      date: bool01(opts.date),
      video: bool01(opts.video),
      calibration: bool01(opts.calibration),
      heatmap: bool01(opts.heatmap),
      speed: bool01(opts.speed)
    ]
  end

  defp bool01(true), do: "1"
  defp bool01(_), do: "0"
end
