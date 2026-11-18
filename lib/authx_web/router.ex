defmodule AuthxWeb.Router do
  use AuthxWeb, :router

  import Oban.Web.Router
  import AshAdmin.Router
  import Phoenix.LiveDashboard.Router
  use AshAuthentication.Phoenix.Router
  use AshAuthentication.Phoenix.Oauth2Server.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AuthxWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  pipeline :admin do
    plug AuthxWeb.Plugs.RequireAdmin
  end

  pipeline :oauth_browser do
    plug :set_actor, :user
  end

  pipeline :oauth_protocol do
    plug :reject_incomplete_oidc_discovery
  end

  pipeline :oidc_api do
    plug :accepts, ["json"]
  end

  pipeline :oidc_userinfo do
    plug AshAuthentication.Phoenix.Oauth2Server.BearerPlug, oauth2_server: Authx.Oauth.Oidc.Server

    plug AshAuthentication.Phoenix.Oauth2Server.RequireScopePlug,
      oauth2_server: Authx.Oauth.Oidc.Server,
      scope: "openid"
  end

  scope "/" do
    pipe_through [:browser, :oauth_browser]
    oauth2_server_consent_routes(oauth2_server: Authx.Oauth.Server)
  end

  scope "/" do
    pipe_through [:api, :oauth_protocol]

    forward "/oauth", AshAuthentication.Phoenix.Oauth2Server.ProtocolRouter,
      oauth2_server: Authx.Oauth.Server
  end

  scope "/", AuthxWeb do
    pipe_through [:browser, :oauth_browser]
    get "/oidc/authorize", OidcController, :authorize
    post "/oidc/authorize", OidcController, :consent
  end

  scope "/", AuthxWeb do
    pipe_through [:oidc_api]
    get "/.well-known/openid-configuration", OidcController, :discovery
    get "/oidc/jwks", OidcController, :jwks
    post "/oidc/token", OidcController, :token
  end

  scope "/", AuthxWeb do
    pipe_through [:oidc_api, :oidc_userinfo]
    get "/oidc/userinfo", OidcController, :userinfo
    post "/oidc/userinfo", OidcController, :userinfo
  end

  scope "/", AuthxWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes,
      on_mount: [{AuthxWeb.LiveUserAuth, :live_user_required}] do
      live "/settings/apps", Settings.AppsLive, :index

      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {AuthxWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {AuthxWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {AuthxWeb.LiveUserAuth, :live_no_user}
    end
  end

  scope "/", AuthxWeb do
    pipe_through :browser

    get "/", PageController, :home
    auth_routes AuthController, Authx.Accounts.User, path: "/auth"

    sign_out_route AuthController, "/sign-out",
      overrides: [AuthxWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove these if you'd like to use your own authentication views
    sign_in_route register_path: "/register",
                  reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{AuthxWeb.LiveUserAuth, :live_no_user}],
                  overrides: [AuthxWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [AuthxWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the confirmation strategy
    confirm_route Authx.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [AuthxWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(Authx.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      overrides: [AuthxWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", AuthxWeb do
  #   pipe_through :api
  # end

  # Enable the Swoosh mailbox preview in development
  if Application.compile_env(:authx, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/" do
    pipe_through [:browser, :admin]

    live_dashboard "/admin/dashboard",
      metrics: AuthxWeb.Telemetry,
      on_mount: [AshAuthentication.Phoenix.LiveSession, {AuthxWeb.AdminAuth, :user}]

    oban_dashboard("/oban",
      resolver: AuthxWeb.ObanResolver,
      on_mount: [{AuthxWeb.AdminAuth, :oban}]
    )

    ash_admin "/admin",
      on_mount: [
        AshAuthentication.Phoenix.LiveSession,
        {AuthxWeb.AdminAuth, :ash_admin}
      ],
      session: [{AshAuthentication.Phoenix.LiveSession, :generate_session, [nil, []]}]
  end

  defp reject_incomplete_oidc_discovery(%{path_info: ["oauth", "openid-configuration"]} = conn, _) do
    conn |> send_resp(404, "") |> halt()
  end

  defp reject_incomplete_oidc_discovery(conn, _), do: conn
end
