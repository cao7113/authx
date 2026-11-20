defmodule Authx.Accounts.UsersTest do
  use Authx.DataCase, async: false

  import Authx.Fixtures

  alias Authx.Accounts.User
  alias Authx.Audit.Event

  test "admin can confirm a user with the default current time and audit it" do
    admin = create_user("user-confirm-admin@example.com", :admin)
    user = Ash.Seed.seed!(User, %{email: "user-unconfirmed@example.com"})
    before = DateTime.utc_now()

    assert {:ok, confirmed} =
             user
             |> Ash.Changeset.for_update(:manual_confirm, %{}, actor: admin)
             |> Ash.update(actor: admin)

    assert DateTime.compare(confirmed.confirmed_at, before) in [:eq, :gt]
    assert {:ok, [event]} = Ash.read(Event, actor: admin)
    assert event.event == "user.confirmed"
    assert event.actor_user_id == admin.id
    assert event.subject_user_id == user.id
  end

  test "admin can set a specific confirmation time" do
    admin = create_user("user-confirm-at-admin@example.com", :admin)
    user = Ash.Seed.seed!(User, %{email: "user-confirm-at@example.com"})
    confirmed_at = ~U[2026-01-02 03:04:05.000000Z]

    assert {:ok, confirmed} =
             user
             |> Ash.Changeset.for_update(:manual_confirm, %{confirmed_at: confirmed_at},
               actor: admin
             )
             |> Ash.update(actor: admin)

    assert confirmed.confirmed_at == confirmed_at
  end

  test "non-admin cannot confirm a user" do
    user = create_user("user-confirm-target@example.com")
    actor = create_user("user-confirm-actor@example.com")

    assert {:error, %Ash.Error.Forbidden{}} =
             user
             |> Ash.Changeset.for_update(:manual_confirm, %{}, actor: actor)
             |> Ash.update(actor: actor, authorize?: true)
  end
end
