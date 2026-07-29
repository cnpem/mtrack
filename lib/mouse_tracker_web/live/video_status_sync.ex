defmodule MouseTrackerWeb.VideoStatusSync do
  @moduledoc """
  Shared mount-time PubSub subscription + status patching for LiveViews that
  show a live-updating list of videos (`ExperimentLive.Index`,
  `ExperimentLive.Show`, `DatasetLive.Index`). Each video's
  `VideoProcessingWorker` topic gets its own subscription so a
  `{:status, video_id, status}` broadcast can patch just that video's status
  in the assigns, without a full reload.
  """

  alias MouseTracker.Workers.VideoProcessingWorker

  @doc "Subscribes the current process to every video's PubSub topic."
  def subscribe_all(videos) do
    Enum.each(
      videos,
      &Phoenix.PubSub.subscribe(MouseTracker.PubSub, VideoProcessingWorker.topic(&1.id))
    )
  end

  @doc "Returns `video` with `status` replaced if its id matches `video_id`."
  def patch_status(video, video_id, status) when video.id == video_id,
    do: %{video | status: status}

  def patch_status(video, _video_id, _status), do: video
end
