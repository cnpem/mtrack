defmodule MouseTracker.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  require Logger
  alias MouseTracker.Repo

  alias MouseTracker.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## OpenID Connect (Keycloak) provisioning

  @doc """
  Gets the local user bound to an OpenID Connect identity.

  The pair `(issuer, sub)` is the identity. `sub` is opaque and stable inside a
  realm; the e-mail and username are attributes that can change at any time.
  """
  def get_user_by_idp_identity(sub, issuer) when is_binary(sub) and is_binary(issuer) do
    Repo.get_by(User, idp_sub: sub, idp_issuer: issuer)
  end

  @doc """
  Resolves the local user for a set of *verified* OIDC claims, provisioning it
  on first login (just-in-time).

  Returns `{:ok, user}` or `{:error, reason}` where `reason` is one of:

    * `:missing_sub` / `:missing_issuer` — the token is unusable
    * `:missing_email` — the app requires an e-mail and Keycloak returned none
      (usually a missing `email` scope, or a user without an address)
    * `:email_in_use` — a *new* identity claims an e-mail that already belongs
      to an existing account, and the claim is not verified

  Linking policy: an existing local account (created before the move to Keycloak,
  or by a seed) is adopted by the incoming identity **only** when
  `email_verified` is true. An unverified e-mail must never be able to take over
  an account — that is an account-takeover primitive, not a convenience.
  """
  def provision_user_from_oidc(claims) when is_map(claims) do
    with {:ok, sub} <- require_claim(claims, :sub),
         {:ok, issuer} <- require_claim(claims, :issuer) do
      case get_user_by_idp_identity(sub, issuer) do
        %User{} = user -> {:ok, sync_claims(user, claims)}
        nil -> provision_first_login(sub, issuer, claims)
      end
    end
  end

  defp provision_first_login(sub, issuer, claims) do
    case claims[:email] do
      email when is_binary(email) and email != "" ->
        case get_user_by_email(email) do
          nil ->
            insert_from_claims(sub, issuer, claims)

          # An account that already belongs to another IdP identity is never
          # re-linked: e-mail is mutable and not authoritative, so allowing it
          # here would let a second identity take over an SSO account.
          %User{idp_sub: linked_sub} when is_binary(linked_sub) ->
            {:error, :email_in_use}

          %User{} = existing ->
            if claims[:email_verified] do
              link_from_claims(existing, sub, issuer, claims)
            else
              {:error, :email_in_use}
            end
        end

      _ ->
        {:error, :missing_email}
    end
  end

  defp insert_from_claims(sub, issuer, claims) do
    %User{}
    |> User.oidc_changeset(%{
      email: claims[:email],
      name: display_name(claims),
      idp_issuer: issuer,
      idp_sub: sub,
      idp_username: claims[:username]
    })
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
    |> Repo.insert()
  end

  defp link_from_claims(%User{} = user, sub, issuer, claims) do
    user
    |> User.oidc_changeset(%{
      idp_issuer: issuer,
      idp_sub: sub,
      idp_username: claims[:username],
      name: user.name || display_name(claims)
    })
    |> Repo.update()
  end

  # Refresh the attributes Keycloak owns. A cosmetic sync must never block a
  # login, so failures are logged and the current row is kept (e.g. if the new
  # e-mail collides with another account, the user is still allowed in).
  defp sync_claims(%User{} = user, claims) do
    attrs = %{
      idp_username: claims[:username] || user.idp_username,
      name: claims[:name] || user.name
    }

    attrs =
      case claims[:email] do
        email when is_binary(email) -> Map.put(attrs, :email, email)
        _ -> attrs
      end

    case user |> User.oidc_changeset(attrs) |> Repo.update() do
      {:ok, user} ->
        user

      {:error, changeset} ->
        Logger.warning(
          "Could not sync OIDC attributes for user #{user.id}: #{inspect(changeset.errors)}"
        )

        user
    end
  end

  defp display_name(claims) do
    claims[:name] || claims[:username] || local_part(claims[:email])
  end

  defp local_part(email) when is_binary(email), do: email |> String.split("@") |> hd()
  defp local_part(_), do: nil

  defp require_claim(claims, key) do
    case Map.get(claims, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :"missing_#{key}"}
    end
  end

  ## User registration

  @doc """
  Registers a user with name, email and password.

  The account is confirmed immediately (`confirmed_at` is set on insert),
  since the user has already proven control of the credentials by choosing a
  password. This avoids ever having an unconfirmed user with a password set,
  a state `login_user_by_magic_link/1` explicitly refuses to handle.

  ## Examples

      iex> register_user(%{name: "Jane", email: "jane@example.com", password: "..."})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for registering a user.

  See `MouseTracker.Accounts.User.registration_changeset/3` for a list of
  supported options.
  """
  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user profile (name/institution).
  """
  def change_user_profile(user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates the user profile (name/institution).
  """
  def update_user_profile(user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing pipeline processing defaults.
  """
  def change_user_pipeline_defaults(user, attrs \\ %{}) do
    User.pipeline_defaults_changeset(user, attrs)
  end

  @doc """
  Updates the user's pipeline processing defaults (threshold/min_area).
  """
  def update_user_pipeline_defaults(user, attrs) do
    user
    |> User.pipeline_defaults_changeset(attrs)
    |> Repo.update()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `MouseTracker.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `MouseTracker.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
