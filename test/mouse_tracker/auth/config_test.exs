defmodule MouseTracker.Auth.ConfigTest do
  @moduledoc """
  Guards the runtime wiring that the mocked provider hides from the rest of the
  suite.

  The `Oidcc.ProviderConfiguration.Worker` only ever starts in dev/prod (tests use
  the Mox mock), so a bad option — an unknown `backoff_type`, a missing issuer —
  is only discovered against a real Keycloak. That is exactly what happened once:
  `:rand_exp` made the worker crash-loop and took the whole application down.
  """

  use ExUnit.Case, async: false

  alias MouseTracker.Auth.Config

  describe "provider_worker_opts/0" do
    test "uses a backoff type the oidcc library actually accepts" do
      opts = Config.provider_worker_opts()

      # `:oidcc_backoff.handle_retry/4` raises FunctionClauseError for an unknown
      # atom, which is how the crash-loop started. Calling it here means the test
      # fails at build time instead of at boot time.
      assert {wait, _state} =
               :oidcc_backoff.handle_retry(
                 opts.backoff_type,
                 opts.backoff_min,
                 opts.backoff_max,
                 :undefined
               )

      assert wait >= opts.backoff_min
    end

    test "never gives up: retries keep coming instead of returning :stop" do
      opts = Config.provider_worker_opts()

      # `:stop` is the only type that aborts after the first failure, and giving
      # up kills the worker — which the application supervisor then restarts
      # until it exceeds its restart intensity and shuts the app down.
      refute opts.backoff_type == :stop

      assert Enum.all?(1..5, fn _ ->
               match?(
                 {_, _},
                 :oidcc_backoff.handle_retry(
                   opts.backoff_type,
                   opts.backoff_min,
                   opts.backoff_max,
                   :undefined
                 )
               )
             end)
    end

    test "allows unsafe HTTP only for a plain-HTTP issuer" do
      previous = Application.get_env(:mouse_tracker, :oidc)

      on_exit(fn -> Application.put_env(:mouse_tracker, :oidc, previous) end)

      # Local `start-dev` Keycloak: HTTP endpoints, so oidcc needs the quirk or
      # it refuses the metadata with {:invalid_config_property, {:uri_https, _}}.
      Application.put_env(
        :mouse_tracker,
        :oidc,
        Keyword.put(previous, :issuer, "http://localhost:8080/realms/mtrack")
      )

      assert Config.insecure_issuer?()
      assert Config.provider_worker_opts().provider_configuration_opts.quirks.allow_unsafe_http

      # Institutional Keycloak: HTTPS, validation stays strict.
      Application.put_env(
        :mouse_tracker,
        :oidc,
        Keyword.put(previous, :issuer, "https://keycloak.example.org/realms/mtrack")
      )

      refute Config.insecure_issuer?()
      refute Config.provider_worker_opts().provider_configuration_opts.quirks.allow_unsafe_http
    end

    test "pins the client authentication method instead of letting oidcc negotiate it" do
      assert Config.client_auth_method() == :client_secret_basic

      previous = Application.get_env(:mouse_tracker, :oidc)

      on_exit(fn -> Application.put_env(:mouse_tracker, :oidc, previous) end)

      Application.put_env(
        :mouse_tracker,
        :oidc,
        Keyword.put(previous, :client_auth_method, "client_secret_post")
      )

      assert Config.client_auth_method() == :client_secret_post
    end

    test "points the worker at the configured issuer under the configured name" do
      opts = Config.provider_worker_opts()

      assert opts.issuer == Config.issuer()
      assert opts.name == Config.provider_name()
      assert is_binary(opts.issuer)
    end
  end
end
