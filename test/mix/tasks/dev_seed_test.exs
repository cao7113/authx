defmodule Mix.Tasks.Dev.SeedTest do
  use Authx.DataCase, async: false

  alias Authx.Accounts.{Admins, User}
  alias Authx.Oauth.Resources.Client

  setup do
    original_env = Mix.env()
    original_shell = Mix.shell()
    original_defaults = Application.fetch_env(:authx, :dev_login_defaults)
    original_demo = Application.fetch_env(:authx, :demo_client_app)
    original_foo = Application.fetch_env(:authx, :foo_client_app)
    original_eim = Application.fetch_env(:authx, :eim_client_app)
    original_eim_extension = Application.fetch_env(:authx, :eim_extension_client_app)

    Mix.env(:dev)
    Mix.shell(Mix.Shell.Process)

    Application.put_env(:authx, :dev_login_defaults, %{
      email: "admin@l.h",
      user_email: "dev@l.h",
      password: "password123456"
    })

    Application.put_env(:authx, :demo_client_app, %{
      client_id: "00000000-0000-7000-8000-000000000001",
      client_name: "Authx local OIDC demo",
      redirect_uri: "http://localhost:4001/auth/user/authx/callback"
    })

    Application.put_env(:authx, :foo_client_app, %{
      client_id: "00000000-0000-7000-8000-000000000002",
      client_name: "Authx Foo local OIDC client",
      redirect_uri: "http://localhost:4002/auth/user/authx/callback",
      callback_env: "AUTHX_FOO_CALLBACK"
    })

    Application.put_env(:authx, :eim_client_app, %{
      client_id: "00000000-0000-7000-8000-000000000003",
      client_name: "Eim local OIDC client",
      redirect_uri: "http://localhost:4003/auth/user/authx/callback",
      callback_env: "AUTHX_EIM_CALLBACK"
    })

    Application.put_env(:authx, :eim_extension_client_app, %{
      client_id: "00000000-0000-7000-8000-000000000004",
      client_name: "Eim browser extension OIDC client",
      redirect_uris: ["https://mkbjhjbecifpejjljcjbadocpfiepoen.chromiumapp.org/"],
      callback_env: "AUTHX_EIM_EXTENSION_CALLBACK"
    })

    on_exit(fn ->
      Mix.env(original_env)
      Mix.shell(original_shell)

      case original_defaults do
        {:ok, defaults} -> Application.put_env(:authx, :dev_login_defaults, defaults)
        :error -> Application.delete_env(:authx, :dev_login_defaults)
      end

      case original_demo do
        {:ok, demo} -> Application.put_env(:authx, :demo_client_app, demo)
        :error -> Application.delete_env(:authx, :demo_client_app)
      end

      case original_foo do
        {:ok, foo} -> Application.put_env(:authx, :foo_client_app, foo)
        :error -> Application.delete_env(:authx, :foo_client_app)
      end

      case original_eim do
        {:ok, eim} -> Application.put_env(:authx, :eim_client_app, eim)
        :error -> Application.delete_env(:authx, :eim_client_app)
      end

      case original_eim_extension do
        {:ok, eim_extension} ->
          Application.put_env(:authx, :eim_extension_client_app, eim_extension)

        :error ->
          Application.delete_env(:authx, :eim_extension_client_app)
      end
    end)

    :ok
  end

  test "creates confirmed users with the development password and is repeatable" do
    Mix.Tasks.Dev.Seed.run([])
    admin = sign_in!("admin@l.h")
    user = sign_in!("dev@l.h")
    assert Admins.admin?(admin.id)
    refute Admins.admin?(user.id)

    Mix.Tasks.Dev.Seed.run([])
    assert Admins.admin?(sign_in!("admin@l.h").id)
    refute Admins.admin?(sign_in!("dev@l.h").id)
  end

  test "grants the role when another administrator exists" do
    existing = Ash.Seed.seed!(User, %{email: "existing-admin@l.h", hashed_password: "test"})
    assert {:ok, _} = Admins.bootstrap("existing-admin@l.h")

    Mix.Tasks.Dev.Seed.run([])
    assert Admins.admin?(sign_in!("admin@l.h").id)
    assert Admins.admin?(existing.id)
  end

  test "refuses to run outside development" do
    Mix.env(:test)

    assert_raise Mix.Error, "mix dev.seed can only be run in the dev environment", fn ->
      Mix.Tasks.Dev.Seed.run([])
    end
  end

  test "registers the configured local OIDC clients" do
    Mix.Tasks.Dev.Seed.run([])

    for {id, redirect_uris} <- [
          {"00000000-0000-7000-8000-000000000001",
           ["http://localhost:4001/auth/user/authx/callback"]},
          {"00000000-0000-7000-8000-000000000002",
           ["http://localhost:4002/auth/user/authx/callback"]},
          {"00000000-0000-7000-8000-000000000003",
           ["http://localhost:4003/auth/user/authx/callback"]},
          {"00000000-0000-7000-8000-000000000004",
           ["https://mkbjhjbecifpejjljcjbadocpfiepoen.chromiumapp.org/"]}
        ] do
      assert {:ok, client} = Ash.get(Client, id, authorize?: false)
      assert client.redirect_uris == redirect_uris
      assert client.scope == "openid email"
      assert client.token_endpoint_auth_method == "none"
      assert client.grant_types == ["authorization_code"]
      assert client.response_types == ["code"]
    end
  end

  defp sign_in!(email) do
    strategy = AshAuthentication.Info.strategy!(User, :password)

    assert {:ok, user} =
             AshAuthentication.Strategy.action(
               strategy,
               :sign_in,
               %{email: email, password: "password123456"},
               []
             )

    user
  end
end
