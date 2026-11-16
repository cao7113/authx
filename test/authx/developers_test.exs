defmodule Authx.DevelopersTest do
  use Authx.DataCase, async: false

  alias Authx.Accounts.User
  alias Authx.Developers

  describe "developer role grant & lookup" do
    test "admin can grant developer role to another user and lookup by id or email" do
      admin = create_user("admin@example.com", :admin)
      user = create_user("alice@example.com", :user)

      refute Developers.developer?(user)
      refute Developers.developer?(user.id)

      assert {:ok, dev} = Developers.grant_developer(user.id, admin)
      assert dev.user_id == user.id
      assert dev.granted_by_user_id == admin.id
      assert dev.status == :active
      assert dev.granted_at != nil

      assert Developers.developer?(user)
      assert Developers.developer?(user.id)

      # Lookup by user_id
      assert {:ok, found} = Developers.get_developer_by_user_id(user.id, actor: admin)
      assert found.id == dev.id

      # Lookup by user_email
      assert {:ok, found_by_email} =
               Developers.get_developer_by_user_email("alice@example.com", actor: admin)

      assert found_by_email.id == dev.id

      # Case insensitive email lookup
      assert {:ok, found_by_upper_email} =
               Developers.get_developer_by_user_email("ALICE@EXAMPLE.COM", actor: admin)

      assert found_by_upper_email.id == dev.id

      # Target user can also look up their own developer record
      assert {:ok, self_found} = Developers.get_developer_by_user_id(user.id, actor: user)
      assert self_found.id == dev.id

      assert {:ok, self_found_email} =
               Developers.get_developer_by_user_email("alice@example.com", actor: user)

      assert self_found_email.id == dev.id
    end

    test "admin can grant developer role by email string directly" do
      admin = create_user("admin-by-email@example.com", :admin)
      user = create_user("bob-grant@example.com", :user)

      assert {:ok, dev} = Developers.grant_developer("bob-grant@example.com", admin)
      assert dev.user_id == user.id
      assert dev.granted_by_user_id == admin.id
      assert Developers.developer?(user)

      # Fails if email does not exist
      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Developers.grant_developer("nonexistent@example.com", admin)

      assert error.message =~ "no user found with email"
    end

    test "grant action requires either email or user_id" do
      admin = create_user("admin-missing@example.com", :admin)

      assert {:error, %Ash.Error.Invalid{errors: [error]}} =
               Developers.grant_developer(%{}, admin)

      assert error.message =~ "must provide either email or user_id"
    end

    test "admin can grant developer role to self" do
      admin = create_user("super-admin@example.com", :admin)

      refute Developers.developer?(admin)

      assert {:ok, dev} = Developers.grant_developer(admin.id, admin)
      assert dev.user_id == admin.id
      assert dev.granted_by_user_id == admin.id
      assert Developers.developer?(admin)
    end

    test "cannot grant developer role twice to the same user" do
      admin = create_user("admin-dup@example.com", :admin)
      user = create_user("dev-dup@example.com", :user)

      assert {:ok, _dev} = Developers.grant_developer(user.id, admin)
      assert {:error, _error} = Developers.grant_developer(user.id, admin)
    end

    test "non-admin cannot grant developer role" do
      user = create_user("normal@example.com", :user)
      target = create_user("target@example.com", :user)

      assert {:error, %Ash.Error.Forbidden{}} = Developers.grant_developer(target.id, user)
      assert {:error, %Ash.Error.Forbidden{}} = Developers.grant_developer(user.id, user)
    end

    test "user cannot view other users' developer records" do
      admin = create_user("admin2@example.com", :admin)
      alice = create_user("alice2@example.com", :user)
      bob = create_user("bob2@example.com", :user)

      assert {:ok, _} = Developers.grant_developer(alice.id, admin)

      # Bob cannot see Alice's developer record (filter restricts visibility)
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Developers.get_developer_by_user_id(alice.id, actor: bob)

      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Developers.get_developer_by_user_email("alice2@example.com", actor: bob)
    end

    test "developer? returns false for invalid arguments or missing users" do
      refute Developers.developer?(nil)
      refute Developers.developer?("not-a-uuid")
      refute Developers.developer?(Ecto.UUID.generate())
    end
  end

  defp create_user(email, role) do
    Ash.Seed.seed!(User, %{email: email, hashed_password: "test_password", role: role})
  end
end
