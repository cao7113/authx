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
    client_resource: Authx.Oauth.Resources.Client,
    authorization_code_resource: Authx.Oauth.Resources.AuthorizationCode,
    refresh_token_resource: Authx.Oauth.Resources.RefreshToken,
    consent_resource: Authx.Oauth.Resources.Consent,
    scopes: ["mcp"],
    dcr_enabled?: false,
    cimd_enabled?: false,
    sign_in_path: "/sign-in"
end
