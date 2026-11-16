defmodule Authx.Developers do
  use Ash.Domain, otp_app: :authx, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Authx.Developers.Developer do
      define :grant_developer_by_email, action: :grant, args: [:email]
      define :grant_developer_by_user_id, action: :grant, args: [:user_id]
      define :get_developer_by_user_id, action: :get_by_user_id, args: [:user_id]
      define :get_developer_by_user_email, action: :get_by_user_email, args: [:email]
    end
  end

  @doc """
  Grants developer role to a user by email, user ID, or user struct.

  `admin_actor` is the admin performing the grant and is required; it is always
  passed to Ash as the `:actor` option. Any `:actor` in `opts` is overridden.
  """
  def grant_developer(target, admin_actor, opts \\ [])

  def grant_developer(%Authx.Accounts.User{id: id}, admin_actor, opts) do
    grant_developer_by_user_id(id, with_actor(opts, admin_actor))
  end

  def grant_developer(target, admin_actor, opts) when is_binary(target) do
    opts = with_actor(opts, admin_actor)

    if String.contains?(target, "@") do
      grant_developer_by_email(target, opts)
    else
      case Ecto.UUID.cast(target) do
        {:ok, uuid} -> grant_developer_by_user_id(uuid, opts)
        _ -> grant_developer_by_email(target, opts)
      end
    end
  end

  def grant_developer(%{} = params, admin_actor, opts) do
    opts = with_actor(opts, admin_actor)

    Authx.Developers.Developer
    |> Ash.Changeset.for_create(:grant, params, opts)
    |> Ash.create(opts)
  end

  defp with_actor(opts, admin_actor), do: Keyword.put(opts, :actor, admin_actor)

  @doc """
  Checks if the given developer record (or developer ID) is active.

  Developer-facing actions take a `Authx.Developers.Developer` as their actor,
  so this re-reads the record instead of trusting a struct captured earlier.
  """
  def active_developer?(%Authx.Developers.Developer{id: id}), do: active_developer?(id)

  def active_developer?(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, valid_id} ->
        case Ash.get(Authx.Developers.Developer, valid_id, authorize?: false) do
          {:ok, %Authx.Developers.Developer{status: :active}} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  def active_developer?(_), do: false

  @doc """
  Checks if the given user (or user ID) is an active developer.
  """
  def developer?(user_or_id) do
    user_id =
      case user_or_id do
        %Authx.Accounts.User{id: id} -> id
        id when is_binary(id) -> id
        _ -> nil
      end

    case Ecto.UUID.cast(user_id) do
      {:ok, valid_id} ->
        case get_developer_by_user_id(valid_id, authorize?: false) do
          {:ok, %Authx.Developers.Developer{status: :active}} -> true
          _ -> false
        end

      _ ->
        false
    end
  end
end
