defmodule MouseTracker.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        MouseTrackerWeb.Telemetry,
        MouseTracker.Repo,
        {DNSCluster, query: Application.get_env(:mouse_tracker, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: MouseTracker.PubSub},
        {Oban, Application.fetch_env!(:mouse_tracker, Oban)}
      ] ++
        oidc_children() ++
        [
          # Start to serve requests, typically the last entry
          MouseTrackerWeb.Endpoint
        ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MouseTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Downloads the realm's discovery document and JWKS at boot, and refreshes
  # them on its own afterwards (so key rotation needs no restart).
  #
  # Skipped when Keycloak is unconfigured — the app still boots and the login
  # screen explains what is missing — and when the provider is mocked, as in
  # tests, so `mix test` never opens a socket to keycloak.example.org.
  defp oidc_children do
    if MouseTracker.Auth.real_provider?() and MouseTracker.Auth.configured?() do
      [{Oidcc.ProviderConfiguration.Worker, MouseTracker.Auth.Config.provider_worker_opts()}]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MouseTrackerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
