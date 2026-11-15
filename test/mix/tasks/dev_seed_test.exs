defmodule Mix.Tasks.Dev.SeedTest do
  use Authx.DataCase, async: false

  alias Authx.Accounts.{Admins, User}

  setup do
    original_env = Mix.env()
    original_shell = Mix.shell()
    original_defaults = Application.fetch_env(:authx, :dev_login_defaults)

    Mix.env(:dev)
    Mix.shell(Mix.Shell.Process)

    Application.put_env(:authx, :dev_login_defaults, %{
      email: "admin@l.h",
      password: "password123456"
    })

    on_exit(fn ->
      Mix.env(original_env)
      Mix.shell(original_shell)

      case original_defaults do
        {:ok, defaults} -> Application.put_env(:authx, :dev_login_defaults, defaults)
        :error -> Application.delete_env(:authx, :dev_login_defaults)
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
