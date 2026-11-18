defmodule Authx.AuditTest do
  use Authx.DataCase, async: false

  import Authx.Fixtures

  alias Authx.Audit
  alias Authx.Audit.Event

  defp record_event do
    assert {:ok, event} =
             Audit.record(%{
               event: "test.event",
               target_type: "oauth_client",
               metadata: %{"note" => "test"}
             })

    event
  end

  test "administrators can read audit events" do
    event = record_event()
    admin = create_user("audit-admin@example.com", :admin)

    assert {:ok, [found]} = Ash.read(Event, actor: admin)
    assert found.id == event.id
  end

  test "plain users and developers cannot read audit events" do
    record_event()
    user = create_user("audit-user@example.com", :user)
    developer = create_developer("audit-developer@example.com")

    assert {:ok, []} = Ash.read(Event, actor: user)
    assert {:ok, []} = Ash.read(Event, actor: developer)
  end

  test "anonymous actors cannot read audit events" do
    record_event()

    assert {:ok, []} = Ash.read(Event)
  end

  test "audit events have no user-facing update or destroy actions" do
    event = record_event()
    admin = create_user("audit-admin-2@example.com", :admin)

    assert {:error, _error} = Ash.destroy(event, actor: admin)

    assert {:ok, [_still_there]} = Ash.read(Event, actor: admin)
  end
end
