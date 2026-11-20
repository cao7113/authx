defmodule Authx.Ops do
  @moduledoc """
  Upper-layer operational entry points for remote shells and mix tasks.

  Emails always identify an Authx **user**. A developer has no email of its
  own; use the email of the user that developer access was granted to.

  Domains operate on records, so this module resolves users and developers
  before calling `Authx.Developers` or `Authx.Oauth.Clients`. Mutations still
  run through Ash policies with the resolved user or developer as the actor;
  only the identity lookup bypasses read authorization.

  Never call this module from the web application.
  """

  alias Authx.Accounts
  alias Authx.Developers
  alias Authx.Oauth.Clients

  @doc """
  Ensures the user identified by `user_email` has developer access.

  `admin_email` identifies the administrator performing the grant. Granting an
  existing developer is a no-op.
  """
  def grant_developer(user_email, admin_email)
      when is_binary(user_email) and is_binary(admin_email) do
    with {:ok, admin} <- Accounts.fetch_admin_by_email(admin_email),
         {:ok, user} <- Accounts.fetch_user_by_email(user_email) do
      Developers.ensure_developer(user, admin)
    end
  end

  @doc """
  Manually confirms a user by email, using the administrator identified by
  `admin_email` as the actor.

  `confirmed_at` defaults to the current UTC time.
  """
  def manual_confirm(user_email, admin_email, confirmed_at \\ DateTime.utc_now())
      when is_binary(user_email) and is_binary(admin_email) do
    with {:ok, admin} <- Accounts.fetch_admin_by_email(admin_email),
         {:ok, user} <- Accounts.fetch_user_by_email(user_email),
         {:ok, confirmed_at} <- cast_confirmed_at(confirmed_at) do
      user
      |> Ash.Changeset.for_update(:manual_confirm, %{confirmed_at: confirmed_at}, actor: admin)
      |> Ash.update(actor: admin)
    end
  end

  defp cast_confirmed_at(%DateTime{} = confirmed_at), do: {:ok, confirmed_at}

  defp cast_confirmed_at(%NaiveDateTime{} = confirmed_at),
    do: DateTime.from_naive(confirmed_at, "Etc/UTC")

  defp cast_confirmed_at(confirmed_at) when is_binary(confirmed_at) do
    case DateTime.from_iso8601(confirmed_at) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :invalid_confirmed_at}
    end
  end

  defp cast_confirmed_at(_confirmed_at), do: {:error, :invalid_confirmed_at}

  @doc """
  Ensures a client named `client_name` exists for the developer identified by
  `user_email`.

  `opts` accepts `:scope` to override the default scope. Ownership always comes
  from the resolved developer, never from the caller.

  redirect_uri like `https://foo.site/auth/user/authx/callback` full path
  """
  def ensure_client(user_email, client_name, redirect_uris, opts \\ [])
      when is_binary(user_email) and is_binary(client_name) do
    with {:ok, developer} <- Developers.fetch_developer_by_user_email(user_email) do
      Clients.ensure(developer, client_name, redirect_uris, Keyword.take(opts, [:scope]))
    end
  end
end
