defmodule MouseTracker.Repo.Migrations.AddOidcIdentityToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # (issuer, sub) is the identity. `sub` is stable inside a realm and is
      # what Keycloak guarantees; e-mail and username can both change, so
      # neither is used to look a user up after the first link.
      add :idp_issuer, :string
      add :idp_sub, :string
      add :idp_username, :string
    end

    # NULLs are distinct in Postgres, so rows that never went through the IdP
    # (users created by seeds/fixtures, or pre-SSO accounts) do not collide.
    create unique_index(:users, [:idp_issuer, :idp_sub], name: :users_idp_issuer_idp_sub_index)
  end
end
