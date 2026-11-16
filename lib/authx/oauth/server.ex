defmodule Authx.Oauth.Server do
  @moduledoc """
  OAuth 2.1 authorization-server configuration.

  See `AshAuthentication.Oauth2Server` for all options.
  """

  use AshAuthentication.Oauth2Server,
    otp_app: :authx,
    user_resource: Authx.Accounts.User,
    issuer_url: {Authx.Secrets, []},
    resource_url: {Authx.Secrets, []},
    signing_secret: {Authx.Secrets, []},
    client_resource: Authx.Oauth.Client,
    authorization_code_resource: Authx.Oauth.AuthorizationCode,
    refresh_token_resource: Authx.Oauth.RefreshToken,
    consent_resource: Authx.Oauth.Consent,
    scopes: ["mcp"],
    dcr_enabled?: false,
    cimd_enabled?: false,
    sign_in_path: "/sign-in"
end
