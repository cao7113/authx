defmodule Authx.Oauth.ClientsTest do
  use Authx.DataCase, async: false

  import Authx.Fixtures

  alias Authx.Developers.Developer
  alias Authx.Oauth.Clients
  alias Authx.Oauth.Resources.Client

  describe "client ownership" do
    test "a developer registers a client and owns it" do
      developer = create_developer("owner@example.com")

      assert {:ok, client} = Clients.register(developer, client_attrs())
      assert client.developer_id == developer.id

      assert {:ok, [found]} = Ash.read(Client, actor: developer)
      assert found.id == client.id
    end

    test "the owner is taken from the actor, not from input" do
      owner = create_developer("owner-input@example.com")
      other = create_developer("other-input@example.com")

      assert {:error, %Ash.Error.Invalid{}} =
               Clients.register(owner, Map.put(client_attrs(), :developer_id, other.id))

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

  describe "client provisioning" do
    test "default_attrs/2 builds complete public-client metadata" do
      attrs = Clients.default_attrs("Provisioned", redirect_uri())

      assert attrs == %{
               client_name: "Provisioned",
               redirect_uris: [redirect_uri()],
               grant_types: ["authorization_code"],
               response_types: ["code"],
               token_endpoint_auth_method: "none",
               scope: "openid email"
             }

      assert Clients.default_attrs("One URI", redirect_uri()).redirect_uris ==
               [redirect_uri()]
    end

    test "ensure/3 creates the client when absent and is repeatable" do
      developer = create_developer("provision@example.com")

      assert {:ok, client} = Clients.ensure(developer, "Provisioned", redirect_uri())
      assert client.developer_id == developer.id

      assert {:ok, again} = Clients.ensure(developer, "Provisioned", redirect_uri())
      assert again.id == client.id
      assert [_] = Clients.list(developer)
    end

    test "ensure/3 returns a conflict instead of overwriting settings" do
      developer = create_developer("conflict@example.com")

      assert {:ok, client} = Clients.ensure(developer, "Conflicting", redirect_uri())

      assert {:error, {:client_mismatch, %{client_id: client_id}}} =
               Clients.ensure(developer, "Conflicting", ["http://localhost:4001/other/callback"])

      assert client_id == client.id

      assert {:ok, reloaded} = Clients.fetch_by_name(developer, "Conflicting")
      assert reloaded.redirect_uris == [redirect_uri()]
    end

    test "ensure/4 accepts a deterministic id only through opts" do
      developer = create_developer("fixed-id@example.com")
      id = Ecto.UUID.generate()

      assert {:ok, client} = Clients.ensure(developer, "Fixed", redirect_uri(), id: id)
      assert client.id == id

      assert {:ok, again} = Clients.ensure(developer, "Fixed", redirect_uri(), id: id)
      assert again.id == client.id
    end

    test "fetch_by_name/2 scopes the lookup to the acting developer" do
      owner = create_developer("fetch-owner@example.com")
      other = create_developer("fetch-other@example.com")
      _client = register_client(owner, %{client_name: "Owned"})

      assert {:ok, %Client{}} = Clients.fetch_by_name(owner, "Owned")
      assert {:error, :not_found} = Clients.fetch_by_name(other, "Owned")
    end

    test "list/1 sorts by name" do
      developer = create_developer("sorted@example.com")
      register_client(developer, %{client_name: "Zeta"})
      register_client(developer, %{client_name: "Alpha"})

      assert [%{client_name: "Alpha"}, %{client_name: "Zeta"}] =
               Clients.list(developer)
    end
  end

  describe "client updates" do
    test "the owner updates the client" do
      developer = create_developer("update-owner@example.com")
      client = register_client(developer, %{client_name: "Updatable"})
      new_uris = ["https://app.example.com/auth/user/authx/callback"]

      assert {:ok, updated} =
               Clients.update(developer, client, %{
                 client_name: "Updated",
                 redirect_uris: new_uris
               })

      assert updated.client_name == "Updated"
      assert updated.redirect_uris == new_uris
    end

    test "another developer cannot update the client" do
      owner = create_developer("update-a@example.com")
      other = create_developer("update-b@example.com")
      client = register_client(owner, %{client_name: "Private"})

      assert {:error, %Ash.Error.Forbidden{}} =
               Clients.update(other, client, %{
                 redirect_uris: ["https://evil.example.com/callback"]
               })
    end

    test "invalid redirect URIs are rejected" do
      developer = create_developer("update-invalid@example.com")
      client = register_client(developer, %{client_name: "Validated"})

      assert {:error, %Ash.Error.Invalid{}} =
               Clients.update(developer, client, %{
                 redirect_uris: ["http://insecure.example.com/callback"]
               })
    end

    test "ownership cannot be changed through input" do
      owner = create_developer("update-keep@example.com")
      other = create_developer("update-steal@example.com")
      client = register_client(owner, %{client_name: "Owned"})

      assert {:error, %Ash.Error.Invalid{}} =
               Clients.update(owner, client, %{developer_id: other.id})
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
