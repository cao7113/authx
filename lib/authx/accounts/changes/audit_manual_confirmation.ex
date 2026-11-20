defmodule Authx.Accounts.Changes.AuditManualConfirmation do
  use Ash.Resource.Change

  alias Authx.Audit

  @impl true
  def change(changeset, _opts, context) do
    actor_user_id = context.actor && context.actor.id

    Ash.Changeset.after_action(changeset, fn _changeset, user ->
      case Audit.record(%{
             event: "user.confirmed",
             actor_user_id: actor_user_id,
             subject_user_id: user.id,
             target_type: "user",
             target_id: user.id,
             metadata: %{
               "email" => to_string(user.email),
               "confirmed_at" => DateTime.to_iso8601(user.confirmed_at)
             }
           }) do
        {:ok, _event} -> {:ok, user}
        {:error, error} -> {:error, error}
      end
    end)
  end
end
