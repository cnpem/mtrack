defmodule MouseTrackerWeb.OIDCController do
  @moduledoc """
  Keycloak login endpoints.

  The browser-facing half of the OpenID Connect authorization-code flow:

      1. GET /users/auth/keycloak
         -> generates state + nonce + PKCE verifier, stores them in the session,
            redirects the browser to Keycloak's authorization endpoint

      2. GET /users/auth/keycloak/callback
         -> checks the returned state against the session, exchanges the code
            for a verified ID token, provisions/links the local user and hands
            off to `UserAuth.log_in_user/2`

  Step 2 ends in the same `user_token` session that `phx.gen.auth` established,
  which is why no LiveView, `Scope` or route guard needs to know that Keycloak
  exists: after this controller, the app is in its normal local session.
  """

  use MouseTrackerWeb, :controller

  require Logger

  alias MouseTracker.Accounts
  alias MouseTracker.Auth
  alias MouseTrackerWeb.UserAuth

  # One-time login state, kept in the session only between `request/2` and
  # `callback/2`. The session cookie is signed (not encrypted), which is fine:
  # the PKCE verifier and nonce are not credentials, and the browser only ever
  # sees them as opaque cookie data.
  @flow_key :oidc_flow

  @error_message "We could not sign you in with Keycloak. Please try again."

  @doc "Starts the login: builds the authorization URL and redirects to Keycloak."
  def request(conn, _params) do
    case Auth.authorization_url() do
      {:ok, url, flow} ->
        conn
        |> put_session(@flow_key, flow)
        |> redirect(external: to_url(url))

      {:error, reason} ->
        fail(conn, :request, reason)
    end
  end

  @doc "Handles Keycloak's redirect back to the app."
  def callback(conn, %{"error" => error} = params) do
    Logger.warning(
      "Keycloak returned an error on the callback: #{error} " <>
        "(#{params["error_description"]})"
    )

    fail(conn, :callback, {:provider_error, error})
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    with {:ok, flow} <- fetch_flow(conn),
         :ok <- verify_state(flow, state),
         {:ok, claims} <- Auth.exchange_code(code, flow),
         {:ok, user} <- Accounts.provision_user_from_oidc(claims) do
      conn
      |> delete_session(@flow_key)
      |> UserAuth.log_in_user(user)
    else
      {:error, reason} -> fail(conn, :callback, reason)
    end
  end

  def callback(conn, _params), do: fail(conn, :callback, :missing_code_or_state)

  # Defensive: the provider contract says `String.t()`, but a provider returning
  # iodata (as `:oidcc` does) must fail as a login error, never as a 500.
  defp to_url(url) when is_binary(url), do: url
  defp to_url(url), do: IO.iodata_to_binary(url)

  ## Flow state

  defp fetch_flow(conn) do
    case get_session(conn, @flow_key) do
      %{} = flow -> {:ok, flow}
      _ -> {:error, :missing_flow}
    end
  end

  # Constant-time comparison, and only when both sides have the same length
  # (Plug.Crypto.secure_compare/2 raises on mismatched sizes).
  defp verify_state(flow, state) when is_binary(state) do
    expected = Map.get(flow, "state")

    if is_binary(expected) and byte_size(expected) == byte_size(state) and
         Plug.Crypto.secure_compare(expected, state) do
      :ok
    else
      {:error, :state_mismatch}
    end
  end

  defp verify_state(_flow, _state), do: {:error, :state_mismatch}

  ## Failure handling

  defp fail(conn, stage, reason) do
    Logger.warning("OIDC login failed (#{stage}): #{inspect(reason)}")

    conn
    |> delete_session(@flow_key)
    |> put_flash(:error, message_for(reason))
    |> redirect(to: ~p"/users/log-in")
  end

  defp message_for(:not_configured),
    do: "Keycloak sign-in is not configured on this server. Contact an administrator."

  defp message_for(reason)
       when reason in [:missing_flow, :state_mismatch, :missing_code_or_state],
       do: "Your sign-in session expired before Keycloak answered. Please try again."

  defp message_for(:missing_email),
    do:
      "Keycloak did not share an e-mail address for your account, and MTrack needs one. " <>
        "Ask an administrator to check the account's e-mail in Keycloak."

  defp message_for(:email_in_use),
    do:
      "An account with this e-mail already exists and Keycloak did not confirm the address " <>
        "as verified. Ask an administrator to link the two accounts."

  defp message_for({:provider_error, _}), do: "Keycloak cancelled or refused the sign-in."

  defp message_for(_reason), do: @error_message
end
