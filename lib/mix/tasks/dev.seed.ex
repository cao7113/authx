defmodule Mix.Tasks.Dev.Seed do
  use Mix.Task

  require Ash.Query

  alias Authx.Accounts.{Admins, User}
  alias Authx.Developers
  alias Authx.Oauth.Client

  @shortdoc "Seeds development users and the local OIDC demo client"

  @moduledoc """
  Creates or updates the local development user and administrator, grants the
  administrator developer access, and registers the local OIDC demo client
  owned by that developer.

  The seed values come from `config :authx` in `config/dev.exs`:

    * `:dev_login_defaults` — administrator email, regular user email and the
      shared development password.
    * `:demo_client_app` — demo client id, name and default redirect URI.

  The demo client always uses the configured fixed id, so local demo
  applications can be configured once. Its redirect URI can be overridden at
  runtime with `AUTHX_DEMO_CALLBACK`.

  This task is only available in the dev environment. It resets both users'
  passwords to the development fixture.
  """

  @impl Mix.Task
  def run(_args) do
    unless Mix.env() == :dev do
      Mix.raise("mix dev.seed can only be run in the dev environment")
    end

    Mix.Task.run("app.start")

    %{email: admin_email, user_email: user_email, password: password} =
      Application.fetch_env!(:authx, :dev_login_defaults)

    {:ok, hashed_password} = AshAuthentication.BcryptProvider.hash(password)

    seed_user!(user_email, hashed_password)
    admin = seed_user!(admin_email, hashed_password)
    ensure_admin!(admin.id, admin_email)
    developer = ensure_developer!(admin)
    client = ensure_demo_client!(developer)

    Mix.shell().info(
      "Development users #{user_email} and #{admin_email} are ready " <>
        "(admin is also a developer).\nAUTHX_CLIENT_ID=#{client.id}"
    )
  end

  defp seed_user!(email, hashed_password) do
    Ash.Seed.upsert!(
      User,
      %{email: email, hashed_password: hashed_password, confirmed_at: DateTime.utc_now()},
      identity: :unique_email
    )
  end

  defp ensure_admin!(id, email) do
    unless Admins.admin?(id) do
      result =
        User
        |> Ash.Query.filter(role == :admin)
        |> Ash.Query.limit(1)
        |> Ash.read_one(domain: Authx.Accounts, authorize?: false)

      case result do
        {:ok, nil} ->
          check_role_result!(Admins.bootstrap(email))

        {:ok, actor} ->
          check_role_result!(Admins.set_role(actor.id, id, :admin))

        {:error, error} ->
          Mix.raise("Could not find an existing administrator: #{inspect(error)}")
      end
    end
  end

  defp check_role_result!({:ok, _user}), do: :ok

  defp check_role_result!({:error, error}) do
    Mix.raise("Could not grant the development administrator role: #{inspect(error)}")
  end

  defp ensure_developer!(%User{} = admin) do
    if Developers.developer?(admin) do
      {:ok, developer} = Developers.get_developer_by_user_id(admin.id, authorize?: false)
      developer
    else
      case Developers.grant_developer(admin, admin) do
        {:ok, developer} -> developer
        {:error, error} -> Mix.raise("Could not grant the developer role: #{inspect(error)}")
      end
    end
  end

  defp ensure_demo_client!(developer) do
    config = demo_config()
    redirect_uri = System.get_env("AUTHX_DEMO_CALLBACK", config.redirect_uri)
    attrs = demo_client_attrs(config.client_name, redirect_uri)

    case Ash.get(Client, config.client_id, authorize?: false, not_found_error?: false) do
      {:ok, nil} ->
        ensure_no_legacy_demo_client!(config)
        register_demo_client!(developer, attrs, config.client_id)

      {:ok, client} ->
        verify_demo_client!(client, attrs, developer, config.client_id)
        client

      {:error, error} ->
        Mix.raise("Could not load the demo client: #{inspect(error)}")
    end
  end

  defp demo_config, do: Application.fetch_env!(:authx, :demo_client_app)

  defp demo_client_attrs(client_name, redirect_uri) do
    %{
      client_name: client_name,
      redirect_uris: [redirect_uri],
      grant_types: ["authorization_code"],
      response_types: ["code"],
      token_endpoint_auth_method: "none",
      scope: "openid email"
    }
  end

  defp register_demo_client!(developer, attrs, client_id) do
    Client
    |> Ash.Changeset.for_create(:register, attrs, actor: developer)
    |> Ash.Changeset.force_change_attribute(:id, client_id)
    |> Ash.create(actor: developer)
    |> case do
      {:ok, client} ->
        client

      {:error, error} ->
        Mix.raise("Could not register the demo client #{client_id}: #{inspect(error)}")
    end
  end

  defp verify_demo_client!(client, attrs, developer, client_id) do
    expected = Map.put(attrs, :developer_id, developer.id)

    if Map.take(client, Map.keys(expected)) == expected do
      :ok
    else
      Mix.raise(
        "Demo client #{client_id} has unexpected settings or owner; " <>
          "inspect or delete it before re-running `mix dev.seed`"
      )
    end
  end

  defp ensure_no_legacy_demo_client!(%{client_name: name, client_id: client_id}) do
    case Client
         |> Ash.Query.filter(client_name == ^name and id != ^client_id)
         |> Ash.read(authorize?: false) do
      {:ok, []} ->
        :ok

      {:ok, clients} ->
        Mix.raise(
          "Found #{length(clients)} demo client(s) without the fixed id " <>
            "#{client_id}; delete them before re-running `mix dev.seed`"
        )

      {:error, error} ->
        Mix.raise("Could not check for existing demo clients: #{inspect(error)}")
    end
  end
end
