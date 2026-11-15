defmodule Authx.Accounts.AdminsTest do
  use Authx.DataCase, async: false

  alias Authx.Accounts.{Admins, User}

  test "bootstrap and role changes require current admin authority and retain an admin" do
    alice = create_user("alice-admin@example.com")
    bob = create_user("bob-admin@example.com")
    assert alice.role == :user

    assert {:error, :forbidden} = Admins.set_role(alice.id, bob.id, :admin)
    assert {:error, :user_not_found} = Admins.bootstrap("missing@example.com")
    assert {:ok, %{role: :admin}} = Admins.bootstrap("ALICE-admin@example.com")
    assert {:error, :already_bootstrapped} = Admins.bootstrap("bob-admin@example.com")
    assert {:error, :last_admin} = Admins.set_role(alice.id, alice.id, :user)
    assert {:ok, %{role: :admin}} = Admins.set_role(alice.id, bob.id, :admin)
    assert {:ok, %{role: :user}} = Admins.set_role(bob.id, alice.id, :user)
    assert {:error, :forbidden} = Admins.set_role(alice.id, bob.id, :user)
    assert {:error, :last_admin} = Admins.set_role(bob.id, bob.id, :user)
  end

  test "registration and direct Ash actions cannot grant admin privileges" do
    user = create_user("policy@example.com")

    changeset =
      Ash.Changeset.for_create(User, :register_with_password, %{
        email: "new@example.com",
        password: "password123456",
        password_confirmation: "password123456",
        role: :admin
      })

    refute changeset.valid?

    assert {:error, %Ash.Error.Forbidden{}} =
             user
             |> Ash.Changeset.for_update(:set_admin_role, %{role: :admin}, actor: user)
             |> Ash.update(actor: user, authorize?: true)

    assert {:error, %Ash.Error.Forbidden{}} =
             user
             |> Ash.Changeset.for_update(:bootstrap_admin, %{}, actor: user)
             |> Ash.update(actor: user, authorize?: true)
  end

  defp create_user(email) do
    Ash.Seed.seed!(User, %{email: email, hashed_password: "test"})
  end
end
