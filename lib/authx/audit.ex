defmodule Authx.Audit do
  @moduledoc """
  Append-only audit events for security-relevant actions.

  Events are written by domain functions, never by user-facing forms. Reads
  are restricted to administrators; the Ash Admin route is additionally
  protected by `AuthxWeb.Plugs.RequireAdmin`.
  """

  use Ash.Domain, otp_app: :authx, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Authx.Audit.Event
  end

  @doc """
  Records one audit event.

  This is an internal, system-facing write: the event name is chosen by the
  calling domain function, never by user input. It bypasses policies because
  audit events have no acting user-writable action; the calling code decides
  what happened and who it happened to.
  """
  def record(attrs) when is_map(attrs) do
    Authx.Audit.Event
    |> Ash.Changeset.for_create(:record, attrs)
    |> Ash.create(authorize?: false)
  end
end
