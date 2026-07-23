defmodule MouseTracker.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `MouseTracker.Accounts` context.
  """

  import Ecto.Query

  alias MouseTracker.Accounts
  alias MouseTracker.Accounts.Scope
  alias MouseTracker.Accounts.User
  alias MouseTracker.Repo

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      name: "Test User",
      password: valid_user_password(),
      password_confirmation: valid_user_password()
    })
  end

  @doc """
  Inserts a user that has never been confirmed and has no password set,
  bypassing `Accounts.register_user/1` (which always requires a password and
  auto-confirms on insert). Mirrors the state a pre-registration-redesign
  user would be in, for tests exercising unconfirmed-user edge cases (e.g.
  `login_user_by_magic_link/1`, the confirmation LiveView).
  """
  def unconfirmed_user_fixture(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{email: unique_user_email()})

    {:ok, user} =
      %User{}
      |> User.email_changeset(attrs)
      |> Repo.insert()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    MouseTracker.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    MouseTracker.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    MouseTracker.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
