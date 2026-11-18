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
  Finds the developer record belonging to the given user email.

  Returns the developer or `nil` when the user has no developer record.
  Lookup failures are raised.
  """
  def find_developer_by_user_email(email) when is_binary(email) do
    Authx.Developers.Developer
    |> Ash.Query.for_read(:get_by_user_email, %{email: String.trim(email)})
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> nil
      {:ok, developer} -> developer
      {:error, error} -> raise error
    end
  end

  @doc """
  Fetches the developer record belonging to the given user email.

  Returns `{:ok, developer}` or `{:error, :not_found}`.
  """
  def fetch_developer_by_user_email(email) when is_binary(email) do
    case find_developer_by_user_email(email) do
      nil -> {:error, :not_found}
      developer -> {:ok, developer}
    end
  end

  @doc """
  Finds the developer record belonging to the given user ID.

  Returns the developer or `nil` when the user has no developer record.
  Lookup failures are raised.
  """
  def find_developer_by_user_id(user_id) when is_binary(user_id) do
    Authx.Developers.Developer
    |> Ash.Query.for_read(:get_by_user_id, %{user_id: user_id})
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> nil
      {:ok, developer} -> developer
      {:error, error} -> raise error
    end
  end

  @doc """
  Ensures `user` has developer access, granting it as `admin`.

  The administrator is passed as the actor so admin policies still apply.
  Granting an existing developer is a no-op.
  """
  def ensure_developer(%Authx.Accounts.User{} = user, %Authx.Accounts.User{} = admin) do
    case find_developer_by_user_id(user.id) do
      nil -> grant_developer(user, admin)
      developer -> {:ok, developer}
    end
  end

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
