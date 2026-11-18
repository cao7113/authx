defmodule Authx.Fixtures do
  @moduledoc """
  Fixtures for users, developers and OAuth clients.
  """

  alias Authx.Accounts.User
  alias Authx.Developers
  alias Authx.Oauth.Clients

  @developer_email "developer@example.com"
  @password "test_password"
  @hashed_password (
                     {:ok, hash} = AshAuthentication.BcryptProvider.hash(@password)
                     hash
                   )
  @redirect_uri "http://localhost:4001/auth/user/authx/callback"

  @client_attrs %{
    client_name: "Test client",
    redirect_uris: [@redirect_uri],
    grant_types: ["authorization_code"],
    response_types: ["code"],
    token_endpoint_auth_method: "none",
    scope: "openid email profile"
  }

  @doc "The client metadata used by `register/2`."
  def client_attrs, do: @client_attrs

  @doc "The redirect URI registered by test clients."
  def redirect_uri, do: @redirect_uri

  @doc "Creates a user with the given email and role."
  def create_user(email, role \\ :user) do
    Ash.Seed.seed!(User, %{
      email: email,
      hashed_password: @hashed_password,
      role: role,
      confirmed_at: DateTime.utc_now()
    })
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
    {:ok, client} = Clients.register(developer, Map.merge(@client_attrs, attrs))
    client
  end

  @doc """
  Grants `user` consent for `client` at `scope`, using the protocol helper so
  tests exercise the same write path as the authorization endpoint.
  """
  def grant_consent(user, client, scope \\ "openid email") do
    AshAuthentication.Oauth2Server.Authorize.grant_consent!(
      Authx.Oauth.Oidc.Server,
      user,
      client,
      scope
    )
  end
end
