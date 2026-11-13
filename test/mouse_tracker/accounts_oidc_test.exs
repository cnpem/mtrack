defmodule MouseTracker.AccountsOIDCTest do
  @moduledoc """
  Provisioning policy for Keycloak identities.

  These are the rules that did not exist with local auth, and the ones most
  likely to be got wrong in a first integration: identity keyed on `sub` rather
  than e-mail, idempotent first login, and the account-takeover guard.
  """

  use MouseTracker.DataCase, async: true

  import MouseTracker.AccountsFixtures

  alias MouseTracker.Accounts
  alias MouseTracker.Accounts.User

  @issuer "https://keycloak.example.org/realms/mtrack"

  defp claims(overrides \\ %{}) do
    Map.merge(
      %{
        sub: "sub-1",
        issuer: @issuer,
        email: "pessoa@example.org",
        email_verified: true,
        name: "Pessoa Teste",
        username: "pessoa"
      },
      overrides
    )
  end

  describe "provision_user_from_oidc/1 - first login" do
    test "creates a confirmed user with no password" do
      assert {:ok, %User{} = user} = Accounts.provision_user_from_oidc(claims())

      assert user.idp_sub == "sub-1"
      assert user.idp_issuer == @issuer
      assert user.email == "pessoa@example.org"
      assert user.name == "Pessoa Teste"
      assert user.confirmed_at
      refute user.hashed_password
    end

    test "falls back to the local part of the e-mail when the provider sends no name" do
      assert {:ok, user} =
               Accounts.provision_user_from_oidc(claims(%{name: nil, username: nil}))

      assert user.name == "pessoa"
    end

    test "requires a subject" do
      assert {:error, :missing_sub} = Accounts.provision_user_from_oidc(claims(%{sub: nil}))
      assert {:error, :missing_sub} = Accounts.provision_user_from_oidc(claims(%{sub: ""}))
    end

    test "requires an issuer" do
      assert {:error, :missing_issuer} = Accounts.provision_user_from_oidc(claims(%{issuer: nil}))
    end

    test "requires an e-mail, which the schema also enforces" do
      assert {:error, :missing_email} = Accounts.provision_user_from_oidc(claims(%{email: nil}))
      assert {:error, :missing_email} = Accounts.provision_user_from_oidc(claims(%{email: ""}))
    end
  end

  describe "provision_user_from_oidc/1 - returning user" do
    test "is idempotent: the same sub never creates a second row" do
      assert {:ok, first} = Accounts.provision_user_from_oidc(claims())
      assert {:ok, second} = Accounts.provision_user_from_oidc(claims())

      assert first.id == second.id
      assert Repo.aggregate(User, :count) == 1
    end

    test "refreshes the attributes Keycloak owns" do
      {:ok, user} = Accounts.provision_user_from_oidc(claims())

      assert {:ok, updated} =
               Accounts.provision_user_from_oidc(
                 claims(%{name: "Nome Novo", email: "outro@example.org", username: "outro"})
               )

      assert updated.id == user.id
      assert updated.name == "Nome Novo"
      assert updated.email == "outro@example.org"
      assert updated.idp_username == "outro"
    end

    test "is keyed on sub, not on e-mail: changing the address in Keycloak keeps the same user" do
      {:ok, user} = Accounts.provision_user_from_oidc(claims())

      {:ok, same} =
        Accounts.provision_user_from_oidc(claims(%{email: "renomeado@example.org"}))

      assert same.id == user.id
    end

    test "the same sub in a different issuer is a different person" do
      {:ok, user} = Accounts.provision_user_from_oidc(claims())

      # A different e-mail is required: `users.email` is unique in the schema,
      # so two identities can never share an address regardless of issuer.
      assert {:ok, other} =
               Accounts.provision_user_from_oidc(
                 claims(%{
                   issuer: "https://outro.example.org/realms/mtrack",
                   email: "outra@example.org"
                 })
               )

      assert other.id != user.id
    end
  end

  describe "provision_user_from_oidc/1 - linking a pre-existing local account" do
    test "links the account when Keycloak confirms the e-mail is verified" do
      existing = user_fixture(%{email: "pessoa@example.org"})

      assert {:ok, user} = Accounts.provision_user_from_oidc(claims())

      assert user.id == existing.id
      assert user.idp_sub == "sub-1"
      # The fixture has no name (it is created through the e-mail changeset), so
      # linking fills the display name from the claims instead of leaving nil.
      assert user.name == "Pessoa Teste"
    end

    test "keeps the local name when the account already had one" do
      existing = user_fixture(%{email: "pessoa@example.org"})
      {:ok, existing} = Accounts.update_user_profile(existing, %{name: "Nome Local"})

      assert {:ok, user} = Accounts.provision_user_from_oidc(claims())

      assert user.id == existing.id
      assert user.name == "Nome Local"
    end

    test "refuses to link when the e-mail is not verified (account takeover guard)" do
      existing = user_fixture(%{email: "pessoa@example.org"})

      assert {:error, :email_in_use} =
               Accounts.provision_user_from_oidc(claims(%{email_verified: false}))

      assert Accounts.get_user!(existing.id).idp_sub == nil
    end

    test "refuses when another identity already owns that e-mail" do
      assert {:ok, other} = Accounts.provision_user_from_oidc(claims(%{sub: "sub-a"}))

      assert other.email == "pessoa@example.org"

      assert {:error, :email_in_use} =
               Accounts.provision_user_from_oidc(claims(%{sub: "sub-b", email_verified: false}))
    end

    test "a verified e-mail already linked to another identity does not hijack it" do
      {:ok, other} = Accounts.provision_user_from_oidc(claims(%{sub: "sub-a"}))

      # Same e-mail, verified, different sub, e.g. a misconfigured mapping in
      # the IdP. Linking by e-mail here would overwrite the first identity.
      assert {:error, :email_in_use} =
               Accounts.provision_user_from_oidc(claims(%{sub: "sub-b"}))

      assert Accounts.get_user_by_idp_identity("sub-a", @issuer).id == other.id
      assert Accounts.get_user_by_idp_identity("sub-b", @issuer) == nil
    end
  end

  describe "get_user_by_idp_identity/2" do
    test "returns nil for an unknown identity" do
      assert Accounts.get_user_by_idp_identity("nope", @issuer) == nil
    end
  end
end
