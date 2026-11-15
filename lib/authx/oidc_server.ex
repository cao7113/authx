defmodule Authx.OidcServer do
  @moduledoc false

  use AshAuthentication.Oauth2Server,
    otp_app: :authx,
    user_resource: Authx.Accounts.User,
    issuer_url: {Authx.Secrets, []},
    resource_url: {Authx.Secrets, []},
    signing_secret: {Authx.Secrets, []},
    client_resource: Authx.Accounts.OauthClient,
    authorization_code_resource: Authx.Accounts.OauthAuthorizationCode,
    refresh_token_resource: Authx.Accounts.OauthRefreshToken,
    consent_resource: Authx.Accounts.OauthConsent,
    scopes: ["openid", "email"],
    dcr_enabled?: false,
    cimd_enabled?: false,
    sign_in_path: "/sign-in"
end
