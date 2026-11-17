# OAuth2 server

The existing OAuth 2.1 routes are mounted only for development and tests.
Dynamic registration and CIMD are disabled; use a pre-registered client.
The development-only OIDC endpoints and client are described in
[client-demo.md](client-demo.md). They are not production-ready.

```
mix igniter.install ash_authentication_oauth2_server
```

- http://localhost:4000/.well-known/openid-configuration

```
Notices:

* OAuth 2.1 server scaffolded.

  1. Wire the OAuth routes into your Phoenix router. Add a
     `use AshAuthentication.Phoenix.Oauth2Server.Router` near the
     top of `MyAppWeb.Router`, then mount the scopes in your
     existing `:browser` and `:api` pipelines:

         scope "/" do
           pipe_through :browser
           oauth2_server_consent_routes oauth2_server: Authx.Oauth2Server
         end

         scope "/" do
           pipe_through :api
           oauth2_server_protocol_routes oauth2_server: Authx.Oauth2Server
         end

  2. Make sure your `:browser` pipeline sets the actor. The consent
     endpoint uses `Ash.PlugHelpers.get_actor/1` to figure out who's
     consenting, so the pipeline needs the standard pair:

         plug :load_from_session
         plug :set_actor, :user

     If the actor isn't set, signed-in users will get bounced through
     the sign-in flow as if they weren't logged in.

  3. Mount the bearer plug on whatever resource(s) you want
     OAuth-protected (an API, MCP endpoint, admin tool, etc.):

         plug AshAuthentication.Phoenix.Oauth2Server.BearerPlug,
           oauth2_server: Authx.Oauth2Server

  4. Run `mix ecto.migrate` to apply the new tables.

  5. The protocol endpoints (`/oauth/register`, `/oauth/token`,
     `/oauth/revoke`) are unauthenticated by design and so are
     reasonable DoS targets. See the "Rate limiting" section of
     `AshAuthentication.Oauth2Server` for a plug-level snippet.

  6. For production, set real values in `config/runtime.exs`:

         config :authx,
           oauth2_issuer_url: System.get_env("OAUTH2_ISSUER_URL"),
           oauth2_resource_url: System.get_env("OAUTH2_RESOURCE_URL"),
           oauth2_signing_secret: System.get_env("OAUTH2_SIGNING_SECRET")


Notices were printed above. Please read them all before continuing!
```