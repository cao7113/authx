defmodule Authx.Fixtures do
  @moduledoc """
  Fixtures for users, developers and OAuth clients.
  """

  alias Authx.Accounts.User
  alias Authx.Developers
  alias Authx.Oauth

  @developer_email "developer@example.com"
  @password "test_password"
  @redirect_uri "http://localhost:4001/auth/user/authx/callback"

  @client_attrs %{
    client_name: "Test client",
    redirect_uris: [@redirect_uri],
    grant_types: ["authorization_code"],
    response_types: ["code"],
    token_endpoint_auth_method: "none",
    scope: "openid email profile"
  }

  @doc "The client metadata used by `register_client/2`."
  def client_attrs, do: @client_attrs

  @doc "The redirect URI registered by test clients."
  def redirect_uri, do: @redirect_uri

  @doc "Creates a user with the given email and role."
  def create_user(email, role \\ :user) do
    Ash.Seed.seed!(User, %{email: email, hashed_password: @password, role: role})
  end

  @doc """
  Creates an active developer: a user with the given email, granted developer
  access by its own administrator.

  Returns the `Authx.Developers.Developer` record, which is the actor
  developer-facing actions take.
  """
  def create_developer(email \\ @developer_email) do
    administrator = create_user("admin-" <> email, :admin)
    user = create_user(email, :user)

    {:ok, developer} = Developers.grant_developer(user.id, administrator)
    developer
  end

  @doc "Registers a client owned by `developer`, with test defaults."
  def register_client(developer, attrs \\ %{}) do
    {:ok, client} = Oauth.register_client(developer, Map.merge(@client_attrs, attrs))
    client
  end
end
