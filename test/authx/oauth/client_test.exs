defmodule Authx.Oauth.ClientTest do
  use Authx.DataCase, async: false

  import Authx.Fixtures

  alias Authx.Developers.Developer
  alias Authx.Oauth
  alias Authx.Oauth.Client

  describe "client ownership" do
    test "a developer registers a client and owns it" do
      developer = create_developer("owner@example.com")

      assert {:ok, client} = Oauth.register_client(developer, client_attrs())
      assert client.developer_id == developer.id

      assert {:ok, [found]} = Ash.read(Client, actor: developer)
      assert found.id == client.id
    end

    test "the owner is taken from the actor, not from input" do
      owner = create_developer("owner-input@example.com")
      other = create_developer("other-input@example.com")

      assert {:error, %Ash.Error.Invalid{}} =
               Oauth.register_client(owner, Map.put(client_attrs(), :developer_id, other.id))

      assert {:ok, []} = Ash.read(Client, actor: other)
    end

    test "a client cannot be registered without an acting developer" do
      changeset = Ash.Changeset.for_create(Client, :register, client_attrs())

      refute changeset.valid?

      assert Enum.any?(changeset.errors, fn error ->
               Exception.message(error) =~ "an active developer must register the client"
             end)

      assert {:error, _error} = Ash.create(changeset)
    end

    test "the actor must be a developer that is still active" do
      # A developer struct that is not (or no longer) an active record cannot
      # be used to register clients.
      stale = %Developer{id: Ecto.UUID.generate(), status: :active}

      changeset = Ash.Changeset.for_create(Client, :register, client_attrs(), actor: stale)

      refute changeset.valid?
      assert {:error, _error} = Ash.create(changeset, actor: stale)
    end
  end

  describe "client visibility" do
    test "developers only see their own clients" do
      owner = create_developer("owner-scope@example.com")
      other = create_developer("other-scope@example.com")
      client = register_client(owner)

      assert {:ok, [found]} = Ash.read(Client, actor: owner)
      assert found.id == client.id

      assert {:ok, []} = Ash.read(Client, actor: other)
    end

    test "a plain user cannot see clients" do
      owner = create_developer("owner-plain@example.com")
      _client = register_client(owner)
      user = create_user("plain@example.com", :user)

      # 普通用户不满足 developer 检查：Ash 会直接拒绝，或在读取时过滤为空。
      case Ash.read(Client, actor: user) do
        {:ok, clients} -> assert clients == []
        {:error, error} -> assert %Ash.Error.Forbidden{} = Ash.Error.to_error_class(error)
      end
    end
  end
end
