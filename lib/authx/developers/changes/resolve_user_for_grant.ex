defmodule Authx.Developers.Changes.ResolveUserForGrant do
  @moduledoc """
  Resolves the user for granting the developer role, prioritizing email lookup,
  and falling back to user_id. Automatically sets granted_by_user_id from actor.
  """
  use Ash.Resource.Change

  alias Authx.Accounts.User

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    email = Ash.Changeset.get_argument(changeset, :email)
    user_id = Ash.Changeset.get_argument(changeset, :user_id)

    changeset =
      if actor && Map.get(actor, :id) do
        Ash.Changeset.force_change_attribute(changeset, :granted_by_user_id, actor.id)
      else
        changeset
      end

    changeset = Ash.Changeset.force_change_attribute(changeset, :status, :active)

    email_str =
      case email do
        %Ash.CiString{string: s} -> s
        s when is_binary(s) -> s
        _ -> nil
      end

    cond do
      is_binary(email_str) and String.trim(email_str) != "" ->
        case User
             |> Ash.Query.filter(email == ^email_str)
             |> Ash.read_one(authorize?: false) do
          {:ok, %User{id: id}} ->
            Ash.Changeset.force_change_attribute(changeset, :user_id, id)

          {:ok, nil} ->
            Ash.Changeset.add_error(changeset,
              field: :email,
              message: "no user found with email #{inspect(email_str)}"
            )

          {:error, error} ->
            Ash.Changeset.add_error(changeset, error)
        end

      not is_nil(user_id) ->
        case User
             |> Ash.Query.filter(id == ^user_id)
             |> Ash.read_one(authorize?: false) do
          {:ok, %User{id: id}} ->
            Ash.Changeset.force_change_attribute(changeset, :user_id, id)

          {:ok, nil} ->
            Ash.Changeset.add_error(changeset,
              field: :user_id,
              message: "no user found with id #{inspect(user_id)}"
            )

          {:error, error} ->
            Ash.Changeset.add_error(changeset, error)
        end

      true ->
        Ash.Changeset.add_error(changeset,
          field: :email,
          message: "must provide either email or user_id"
        )
    end
  end
end
