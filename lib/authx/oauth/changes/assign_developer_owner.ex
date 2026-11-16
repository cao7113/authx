defmodule Authx.Oauth.Changes.AssignDeveloperOwner do
  @moduledoc """
  Sets a new client's owning developer from the acting developer.

  The owner never comes from input: `developer_id` is taken from the actor,
  which must be an active `Authx.Developers.Developer`. The check runs even
  when authorization is disabled (mix tasks, tests, internal callers), so no
  call path can create an unowned client or one owned by a suspended
  developer.
  """

  use Ash.Resource.Change

  alias Authx.Developers.Developer

  @impl true
  def change(changeset, _opts, %{actor: %Developer{} = developer}) do
    if Authx.Developers.active_developer?(developer) do
      Ash.Changeset.force_change_attribute(changeset, :developer_id, developer.id)
    else
      reject(changeset)
    end
  end

  def change(changeset, _opts, _context), do: reject(changeset)

  defp reject(changeset) do
    Ash.Changeset.add_error(changeset,
      field: :developer_id,
      message: "an active developer must register the client"
    )
  end
end
