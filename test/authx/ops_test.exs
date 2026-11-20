defmodule Authx.OpsTest do
  use Authx.DataCase, async: false

  import Authx.Fixtures

  alias Authx.Ops

  describe "grant_developer/2" do
    test "grants developer access using the administrator as the actor" do
      admin = create_user("ops-admin@example.com", :admin)
      user = create_user("ops-grantee@example.com", :user)

      assert {:ok, developer} =
               Ops.grant_developer("ops-grantee@example.com", "ops-admin@example.com")

      assert developer.user_id == user.id
      assert developer.granted_by_user_id == admin.id
    end

    test "is idempotent for an existing developer" do
      developer = create_developer("ops-idempotent@example.com")

      assert {:ok, again} =
               Ops.grant_developer(
                 "ops-idempotent@example.com",
                 "admin-ops-idempotent@example.com"
               )

      assert again.id == developer.id
    end

    test "rejects a non-administrator actor" do
      _actor = create_user("ops-not-admin@example.com", :user)
      _target = create_user("ops-target@example.com", :user)

      assert {:error, :not_admin} =
               Ops.grant_developer("ops-target@example.com", "ops-not-admin@example.com")
    end

    test "reports missing users" do
      _admin = create_user("ops-missing-admin@example.com", :admin)

      assert {:error, :not_found} =
               Ops.grant_developer("ops-ghost@example.com", "ops-missing-admin@example.com")

      assert {:error, :not_found} =
               Ops.grant_developer("ops-ghost@example.com", "ops-no-admin@example.com")
    end
  end

  describe "manual_confirm/3" do
    test "confirms a user by email through the User action" do
      admin = create_user("ops-manual-confirm-admin@example.com", :admin)
      user = Ash.Seed.seed!(Authx.Accounts.User, %{email: "ops-manual-confirm@example.com"})
      confirmed_at = ~U[2026-01-02 03:04:05.000000Z]

      assert {:ok, confirmed} =
               Ops.manual_confirm(
                 "ops-manual-confirm@example.com",
                 to_string(admin.email),
                 confirmed_at
               )

      assert confirmed.id == user.id
      assert confirmed.confirmed_at == confirmed_at
    end
  end

  describe "ensure_client/3" do
    test "creates a client owned by the resolved developer with default metadata" do
      developer = create_developer("ops-client@example.com")

      assert {:ok, client} =
               Ops.ensure_client("ops-client@example.com", "Ops client", redirect_uri())

      assert client.developer_id == developer.id
      assert client.grant_types == ["authorization_code"]
      assert client.response_types == ["code"]
      assert client.token_endpoint_auth_method == "none"
      assert client.scope == "openid email"
    end

    test "allows overriding the scope" do
      _developer = create_developer("ops-scope@example.com")

      assert {:ok, client} =
               Ops.ensure_client("ops-scope@example.com", "Ops scoped", redirect_uri(),
                 scope: "openid email profile"
               )

      assert client.scope == "openid email profile"
    end

    test "requires a developer" do
      _user = create_user("ops-no-dev@example.com", :user)

      assert {:error, :not_found} =
               Ops.ensure_client("ops-no-dev@example.com", "Nope", redirect_uri())
    end
  end
end
