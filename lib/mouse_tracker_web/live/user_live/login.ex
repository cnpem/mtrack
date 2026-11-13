defmodule MouseTrackerWeb.UserLive.Login do
  @moduledoc """
  The single entry point into the app.

  There is no form here: credentials are collected by Keycloak, and the whole
  flow is a plain browser redirect to `/users/auth/keycloak`. This screen exists
  to explain that, to fail loudly when the deployment is misconfigured (instead
  of bouncing the user to a broken authorization URL), and to host the
  dev-only shortcut used when the realm is unreachable from a dev machine.
  """

  use MouseTrackerWeb, :live_view

  alias MouseTracker.Auth
  alias MouseTracker.Auth.Config

  # `dev_routes` is compile-time config (it decides whether the router mounts
  # the dev-only shortcut), so it must be read in the module body.
  @dev_routes_enabled Application.compile_env(:mouse_tracker, :dev_routes, false)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <h1 class="text-lg font-semibold text-[#0f1729]">Log in</h1>
        <p class="mt-1.5 text-sm text-[#667085]">
          <%= if @current_scope do %>
            You need to reauthenticate to perform sensitive actions on your account.
          <% else %>
            MTrack uses your institution's Keycloak account — there is no separate MTrack
            password.
          <% end %>
        </p>
      </div>

      <a
        :if={@configured}
        href="/users/auth/keycloak"
        class="mt-6 flex w-full items-center justify-center gap-2 rounded-[8px] bg-[#CC5500] px-4 py-2.5 text-[14px] font-semibold text-white hover:bg-[#b34a00]"
      >
        Continue with Keycloak <span aria-hidden="true">→</span>
      </a>

      <div
        :if={!@configured}
        class="mt-6 flex items-start gap-2.5 rounded-[8px] border border-red-200 bg-red-50 p-3 text-sm text-red-700"
      >
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
        <div>
          <p class="font-semibold">Keycloak is not configured on this server.</p>
          <p class="mt-1">Set the following environment variables and restart MTrack:</p>
          <ul class="mt-2 space-y-0.5 font-mono text-[12px]">
            <li :for={var <- @missing_env_vars}>{var}</li>
          </ul>
        </div>
      </div>

      <div :if={@dev_login} class="mt-6 rounded-[8px] border border-dashed border-[#e7e9ee] p-3">
        <p class="text-[11px] font-medium uppercase tracking-wide text-[#98a2b3]">
          Development only
        </p>
        <p class="mt-1.5 text-sm text-[#667085]">
          Skip Keycloak by signing in as a local user (the route only exists when
          <code class="font-mono text-[12px]">:dev_routes</code>
          is on):
        </p>
        <div class="mt-2 flex flex-wrap gap-2">
          <a
            href="/dev/login?email=demo@locomo.dev"
            class="rounded-[8px] border border-[#e7e9ee] px-3 py-1.5 text-sm font-medium text-[#344054] hover:bg-[#f3f4f6]"
          >
            demo@locomo.dev
          </a>
        </div>
      </div>
    </Layouts.auth>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       configured: Auth.configured?(),
       missing_env_vars: Enum.map(Config.missing_settings(), &Config.env_var_for/1),
       dev_login: @dev_routes_enabled
     )}
  end
end
