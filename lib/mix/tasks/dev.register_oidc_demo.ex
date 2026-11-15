defmodule Mix.Tasks.Dev.RegisterOidcDemo do
  use Mix.Task
  require Ash.Query

  alias Authx.Accounts.OauthClient

  @shortdoc "Registers the local OIDC demo client"
  @name "Authx local OIDC demo"
  @default_redirect_uri "http://localhost:4001/auth/user/authx/callback"

  @impl true
  def run(_args) do
    unless Mix.env() == :dev, do: Mix.raise("This task is only available in development")
    Mix.Task.run("app.start")
    redirect_uri = System.get_env("AUTHX_DEMO_CALLBACK", @default_redirect_uri)

    clients =
      OauthClient
      |> Ash.Query.filter(client_name == ^@name)
      |> Ash.read!(authorize?: false)

    client =
      case clients do
        [] ->
          OauthClient
          |> Ash.Changeset.for_create(:register, %{
            client_name: @name,
            redirect_uris: [redirect_uri],
            grant_types: ["authorization_code"],
            response_types: ["code"],
            token_endpoint_auth_method: "none",
            scope: "openid email"
          })
          |> Ash.create!(authorize?: false)

        [client] ->
          unless client.redirect_uris == [redirect_uri] and client.scope == "openid email" and
                   client.grant_types == ["authorization_code"] and
                   client.response_types == ["code"] and
                   client.token_endpoint_auth_method == "none" do
            Mix.raise(
              "Existing demo client has unexpected settings; inspect it before proceeding"
            )
          end

          client

        _ ->
          Mix.raise("Multiple demo clients exist; inspect them before proceeding")
      end

    Mix.shell().info("AUTHX_CLIENT_ID=#{client.id}")
  end
end
