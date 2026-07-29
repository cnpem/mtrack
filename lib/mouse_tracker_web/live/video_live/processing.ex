defmodule MouseTrackerWeb.VideoLive.Processing do
  use MouseTrackerWeb, :live_view

  alias MouseTracker.Experiments
  alias MouseTracker.Workers.VideoProcessingWorker

  @max_log_lines 40

  @impl true
  def mount(%{"video_id" => id}, _session, socket) do
    video = Experiments.get_video_with_experiment!(id)

    # Scope check: the video's experiment must belong to the current user.
    if video.experiment.user_id != socket.assigns.current_scope.user.id do
      raise Ecto.NoResultsError, queryable: MouseTracker.Experiments.Video
    end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(MouseTracker.PubSub, VideoProcessingWorker.topic(video.id))
    end

    {:ok,
     socket
     |> assign(:page_title, "Processing")
     |> assign(:video, video)
     |> assign(:status, video.status)
     |> assign(:progress, initial_progress(video.status))
     |> assign(:log, initial_log(video.status))}
  end

  @impl true
  def handle_info({:progress, _id, value}, socket) do
    pct = value |> to_float() |> clamp()

    {:noreply,
     socket
     |> assign(:progress, pct)
     |> assign(:status, "processing")
     |> push_log("frame progress · #{format_pct(pct)}%")}
  end

  def handle_info({:status, _id, status}, socket) do
    {:noreply, assign(socket, :status, status)}
  end

  def handle_info({:processing_done, _id}, socket) do
    {:noreply,
     socket
     |> assign(:status, "done")
     |> assign(:progress, 100.0)
     |> push_log("done · tracking result saved")}
  end

  def handle_info({:processing_error, _id, reason}, socket) do
    {:noreply,
     socket
     |> assign(:status, "error")
     |> push_log("error · #{inspect_reason(reason)}")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.locomo
      flash={@flash}
      current_scope={@current_scope}
      active={:experiments}
      breadcrumb={@video.experiment.name}
      page_title="Processing"
    >
      <div class="mx-auto max-w-[980px]">
        <.link
          navigate={~p"/experiments/#{@video.experiment_id}"}
          class="inline-flex items-center gap-1 text-[12.5px] text-[#667085] hover:text-[#0f1729]"
        >
          <.icon name="hero-chevron-left-micro" class="size-4" /> {@video.experiment.name}
        </.link>

        <div class="mt-3 rounded-[13px] border border-[#e7e9ee] bg-white p-[22px] shadow-[0_1px_2px_rgba(16,24,40,.04)]">
          <div class="flex items-center gap-2">
            <span class={[
              "size-2.5 rounded-full",
              @status == "done" && "bg-[#12b76a]",
              @status == "error" && "bg-[#d92d20]",
              @status not in ["done", "error"] && "bg-[#CC5500] locomo-pulse"
            ]}></span>
            <span class="text-[14px] font-bold text-[#0f1729]">{status_headline(@status)}</span>
            <span class="truncate font-data text-[12px] text-[#8a93a3]">{@video.filename}</span>
          </div>

          <div class="mt-4 font-data text-[38px] font-semibold leading-none text-[#CC5500]">
            {format_pct(@progress)}<span class="text-[20px] text-[#e0a985]">%</span>
          </div>

          <div class="mt-4 h-2.5 w-full overflow-hidden rounded-full bg-[#f2f4f7]">
            <div
              class="relative h-full rounded-full bg-gradient-to-r from-[#CC5500] to-[#e0842f] transition-[width] duration-300"
              style={"width:#{format_pct(@progress)}%"}
            >
              <div
                :if={@status not in ["done", "error"]}
                class="absolute inset-0 bg-gradient-to-r from-transparent via-white/40 to-transparent locomo-shimmer"
              >
              </div>
            </div>
          </div>

          <div class="mt-2 font-data text-[11.5px] text-[#98a2b3]">
            {stage_label(@progress, @status)}
          </div>
        </div>

        <div class="mt-4 grid grid-cols-1 gap-4 lg:grid-cols-2">
          <div class="rounded-[13px] border border-[#e7e9ee] bg-white p-[18px] shadow-[0_1px_2px_rgba(16,24,40,.04)]">
            <div class="text-[13px] font-bold text-[#0f1729]">Pipeline</div>
            <ul class="mt-3 space-y-3">
              <.pipeline_step
                :for={step <- pipeline_steps(@progress, @status)}
                state={step.state}
                label={step.label}
                note={step.note}
              />
            </ul>
          </div>

          <div class="flex flex-col rounded-[13px] border border-[#e7e9ee] bg-[#11161f] p-[18px]">
            <div class="text-[13px] font-bold text-white/90">Worker output</div>
            <div class="mt-3 flex-1 space-y-1.5 overflow-y-auto font-data text-[11.5px] leading-relaxed">
              <div
                :for={{line, idx} <- Enum.with_index(@log)}
                class={[
                  idx == length(@log) - 1 && "text-[#e0842f]",
                  idx != length(@log) - 1 && "text-[#7e8794]"
                ]}
              >
                <span class="text-[#475467]">›</span> {line}<span
                  :if={idx == length(@log) - 1 and @status not in ["done", "error"]}
                  class="ml-0.5 inline-block h-3 w-1.5 bg-[#e0842f] align-middle locomo-blink"
                ></span>
              </div>
            </div>
          </div>
        </div>

        <div :if={@status == "done"} class="mt-4 flex justify-end">
          <.button navigate={~p"/experiments/#{@video.experiment_id}/results?#{[video: @video.id]}"}>
            View results
          </.button>
        </div>
      </div>
    </Layouts.locomo>
    """
  end

  attr :state, :atom, required: true
  attr :label, :string, required: true
  attr :note, :string, required: true

  defp pipeline_step(assigns) do
    ~H"""
    <li class="flex items-start gap-3">
      <span class={[
        "mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full",
        @state == :done && "bg-[#CC5500] text-white",
        @state == :running && "border-[1.5px] border-[#CC5500] border-t-transparent locomo-spin",
        @state == :queued && "border-[1.5px] border-[#d4d8df]"
      ]}>
        <.icon :if={@state == :done} name="hero-check-micro" class="size-3.5" />
      </span>
      <div>
        <div class={[
          "text-[13px] font-medium",
          @state == :queued && "text-[#98a2b3]",
          @state != :queued && "text-[#0f1729]"
        ]}>
          {@label}
        </div>
        <div class="text-[11.5px] text-[#98a2b3]">{@note}</div>
      </div>
    </li>
    """
  end

  # --- progress / status helpers ---

  defp initial_progress("done"), do: 100.0
  defp initial_progress(_), do: 0.0

  defp initial_log("done"), do: ["done · tracking result saved"]
  defp initial_log("error"), do: ["error · processing failed"]
  defp initial_log("processing"), do: ["worker running · waiting for frames…"]
  defp initial_log(_), do: ["queued · waiting for a worker…"]

  defp push_log(socket, line) do
    log = (socket.assigns.log ++ [line]) |> Enum.take(-@max_log_lines)
    assign(socket, :log, log)
  end

  defp status_headline("done"), do: "Processing complete"
  defp status_headline("error"), do: "Processing failed"
  defp status_headline(_), do: "Processing video"

  # The Python pipeline emits a single % (frames processed), not named stages, so
  # the step list is a heuristic derived from that %. Documented in CLAUDE.md.
  defp pipeline_steps(progress, status) do
    [
      %{
        label: "Decode video",
        note: "Read frames and metadata",
        state: step_state(progress, status, 0, 5)
      },
      %{
        label: "Detect & track",
        note: "Background diff + contour tracking per frame",
        state: step_state(progress, status, 5, 95)
      },
      %{
        label: "Kinematics & render",
        note: "Distance, speed, ROI occupancy, heatmap",
        state: step_state(progress, status, 95, 100)
      }
    ]
  end

  defp step_state(_progress, "done", _from, _to), do: :done
  defp step_state(_progress, "error", _from, _to), do: :queued

  defp step_state(progress, _status, from, to) do
    cond do
      progress >= to -> :done
      progress >= from -> :running
      true -> :queued
    end
  end

  defp stage_label(_progress, "done"), do: "Finished · result saved"
  defp stage_label(_progress, "error"), do: "Stopped on error"
  defp stage_label(progress, _status), do: "Tracking · #{format_pct(progress)}% of frames"

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(v) when is_binary(v), do: String.to_float(v)
  defp to_float(_), do: 0.0

  defp clamp(v) when v < 0, do: 0.0
  defp clamp(v) when v > 100, do: 100.0
  defp clamp(v), do: v * 1.0

  defp format_pct(v), do: :erlang.float_to_binary(v * 1.0, decimals: 1)

  defp inspect_reason(reason) when is_binary(reason), do: reason
  defp inspect_reason(reason), do: inspect(reason)
end
