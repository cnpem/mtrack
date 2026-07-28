defmodule MouseTrackerWeb.Router do
  use MouseTrackerWeb, :router

  import MouseTrackerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MouseTrackerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MouseTrackerWeb do
    pipe_through :browser

    get "/", RootRedirectController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", MouseTrackerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:mouse_tracker, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MouseTrackerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", MouseTrackerWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{MouseTrackerWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      # Locomo main flow. Static segments (`/new`) must be declared before the
      # `/:id` catch-all so they are not captured as an experiment id.
      live "/experiments", ExperimentLive.Index, :index
      live "/experiments/new", ExperimentLive.New, :upload
      live "/experiments/new/roi", ExperimentLive.New, :roi
      live "/experiments/new/review", ExperimentLive.New, :review
      live "/experiments/:id", ExperimentLive.Show, :show
      live "/experiments/:id/results", ExperimentLive.Results, :results
      live "/videos/:video_id/processing", VideoLive.Processing, :show
      live "/videos/:video_id/rois/:roi_id/edit", ExperimentLive.RoiEdit, :edit
      live "/datasets", DatasetLive.Index, :index

      live "/analyses", AnalysesLive.Index, :index
      live "/pipeline-settings", PipelineSettingsLive.Index, :index
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", MouseTrackerWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{MouseTrackerWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
