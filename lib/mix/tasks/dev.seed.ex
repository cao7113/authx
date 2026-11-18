defmodule Mix.Tasks.Dev.Seed do
  use Mix.Task

  require Ash.Query

  alias Authx.Accounts.{Admins, User}
  alias Authx.Oauth.Clients
  alias Authx.Ops

  @shortdoc "Seeds development users and local OIDC clients"

  @moduledoc """
  Creates or updates the local development user and administrator, grants the
  administrator developer access, and registers the local OIDC clients owned by
  that developer.

  The seed values come from `config :authx` in `config/dev.exs`:

    * `:dev_login_defaults` — administrator email, regular user email and the
      shared development password.
    * `:demo_client_app` — demo client id, name and default redirect URI.
    * `:foo_client_app` — foo client id, name and default redirect URI.

  Every configured client always uses its fixed id, so local demo applications
  can be configured once. A client's redirect URI can be overridden at runtime
  with its `:callback_env` variable (for example `AUTHX_DEMO_CALLBACK` or
  `AUTHX_FOO_CALLBACK`).

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
    developer = ensure_developer!(admin_email)
    clients = Enum.map(client_configs(), &ensure_client!(developer, &1))

    Mix.shell().info(
      "Development users #{user_email} and #{admin_email} are ready " <>
        "(admin is also a developer).\n" <>
        Enum.map_join(clients, "\n", fn client ->
          "AUTHX_CLIENT_ID=#{client.id} (#{client.client_name})"
        end)
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

  defp ensure_developer!(email) do
    case Ops.grant_developer(email, email) do
      {:ok, developer} -> developer
      {:error, reason} -> Mix.raise("Could not grant the developer role: #{inspect(reason)}")
    end
  end

  defp ensure_client!(developer, config) do
    redirect_uri = System.get_env(callback_env(config), config.redirect_uri)

    case Clients.ensure(developer, config.client_name, redirect_uri, id: config.client_id) do
      {:ok, client} ->
        client

      {:error, reason} ->
        Mix.raise(
          "Could not ensure the client #{config.client_id}: #{inspect(reason)}; " <>
            "inspect or delete it before re-running `mix dev.seed`"
        )
    end
  end

  defp client_configs do
    [:demo_client_app, :foo_client_app]
    |> Enum.flat_map(fn key ->
      case Application.fetch_env(:authx, key) do
        {:ok, config} -> [config]
        :error -> []
      end
    end)
  end

  defp callback_env(config), do: Map.get(config, :callback_env, "AUTHX_DEMO_CALLBACK")
end
