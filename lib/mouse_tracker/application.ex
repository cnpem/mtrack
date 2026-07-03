defmodule MouseTracker.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MouseTrackerWeb.Telemetry,
      MouseTracker.Repo,
      {DNSCluster, query: Application.get_env(:mouse_tracker, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MouseTracker.PubSub},
      {Oban, Application.fetch_env!(:mouse_tracker, Oban)},
      # Start to serve requests, typically the last entry
      MouseTrackerWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MouseTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MouseTrackerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
