defmodule Authx.Oauth.Clients do
  @moduledoc """
  Client registration and lookup operations for the OAuth domain.

  Every function takes a `Authx.Developers.Developer` as the acting actor;
  ownership and visibility are enforced by the client policies.
  """

  require Ash.Query

  alias Authx.Oauth.Resources.Client

  @list_attributes [:redirect_uris, :grant_types, :response_types]

  @doc """
  Returns the default registration attributes for a public OIDC client.

  Both the developer console and operational entry points use this function so
  the defaults cannot drift. `redirect_uris` may be a single URI or a list.
  """
  def default_attrs(client_name, redirect_uris) do
    %{
      client_name: client_name,
      redirect_uris: List.wrap(redirect_uris),
      grant_types: ["authorization_code"],
      response_types: ["code"],
      token_endpoint_auth_method: "none",
      scope: "openid email"
    }
  end

  @doc """
  Registers a client owned by `developer`.

  The given developer is passed to Ash as the actor and is the only source of
  ownership; any `:actor` in `opts` is overridden and ownership can never be
  supplied as input.

  The `:id` option is reserved for deterministic development fixtures and is
  intentionally not exposed by operational entry points.
  """
  def register(developer, attrs, opts \\ []) do
    {id, opts} = Keyword.pop(opts, :id)
    opts = Keyword.put(opts, :actor, developer)

    Client
    |> Ash.Changeset.for_create(:register, attrs, opts)
    |> force_id(id)
    |> Ash.create(opts)
  end

  @doc """
  Updates a client owned by `developer`.

  Only the owning developer can update its clients; ownership itself is never
  accepted as input.
  """
  def update(developer, %Client{} = client, attrs) do
    client
    |> Ash.Changeset.for_update(:update, attrs, actor: developer)
    |> Ash.update(actor: developer)
  end

  @doc """
  Fetches one of `developer`'s clients by name.

  Returns `{:ok, client}`, `{:error, :not_found}` when it does not exist, or
  `{:error, error}`. Only the acting developer's clients are visible.
  """
  def fetch_by_name(developer, client_name) when is_binary(client_name) do
    Client
    |> Ash.Query.filter(client_name == ^client_name and developer_id == ^developer.id)
    |> Ash.Query.limit(1)
    |> Ash.read_one(actor: developer)
    |> to_fetch_result()
  end

  @doc """
  Fetches one of `developer`'s clients by id.

  Returns `{:ok, client}`, `{:error, :not_found}` when it does not exist, or
  `{:error, error}`.
  """
  def fetch_by_id(developer, client_id) when is_binary(client_id) do
    case Ecto.UUID.cast(client_id) do
      {:ok, uuid} ->
        Client
        |> Ash.Query.filter(id == ^uuid and developer_id == ^developer.id)
        |> Ash.read_one(actor: developer)
        |> to_fetch_result()

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns all clients owned by `developer`, sorted by name.

  Always returns a list; read failures are raised.
  """
  def list(developer) do
    Client
    |> Ash.Query.filter(developer_id == ^developer.id)
    |> Ash.Query.sort(client_name: :asc)
    |> Ash.read!(actor: developer)
  end

  @doc """
  Ensures a client named `client_name` exists for `developer`.

  Other metadata is filled from `default_attrs/2`. `opts` accepts `:scope` to
  override the default scope, and `:id` for deterministic development
  fixtures; operational entry points must not pass `:id`.

  The client is created when absent. When it already exists, its attributes are
  compared with the resolved attrs and a conflict is returned instead of
  silently overwriting production settings.
  """
  def ensure(developer, client_name, redirect_uris, opts \\ []) do
    {scope, opts} = Keyword.pop(opts, :scope)
    attrs = default_attrs(client_name, redirect_uris) |> put_scope(scope)

    case find_existing(developer, client_name, opts) do
      {:error, :not_found} -> register(developer, attrs, opts)
      {:ok, client} -> verify(client, attrs, developer)
      {:error, error} -> {:error, error}
    end
  end

  defp put_scope(attrs, nil), do: attrs
  defp put_scope(attrs, scope) when is_binary(scope), do: %{attrs | scope: scope}

  defp find_existing(developer, client_name, opts) do
    case Keyword.get(opts, :id) do
      nil ->
        fetch_by_name(developer, client_name)

      id when is_binary(id) ->
        case fetch_by_id(developer, id) do
          {:error, :not_found} -> fetch_by_name(developer, client_name)
          result -> result
        end
    end
  end

  defp force_id(changeset, nil), do: changeset

  defp force_id(changeset, id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Ash.Changeset.force_change_attribute(changeset, :id, uuid)
      :error -> raise ArgumentError, "client id must be a valid UUID, got: #{inspect(id)}"
    end
  end

  defp verify(client, attrs, developer) do
    expected = Map.put(attrs, :developer_id, developer.id)
    actual = Map.take(client, Map.keys(expected))

    if equivalent?(actual, expected) do
      {:ok, client}
    else
      {:error, {:client_mismatch, %{client_id: client.id, expected: expected, actual: actual}}}
    end
  end

  defp equivalent?(actual, expected) do
    Enum.all?(expected, fn {key, value} ->
      if key in @list_attributes do
        sort_list(Map.get(actual, key)) == sort_list(value)
      else
        Map.get(actual, key) == value
      end
    end)
  end

  defp to_fetch_result({:ok, nil}), do: {:error, :not_found}
  defp to_fetch_result(result), do: result

  defp sort_list(value) when is_list(value), do: Enum.sort(value)
  defp sort_list(value), do: value
end
