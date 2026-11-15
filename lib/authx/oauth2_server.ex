defmodule Authx.Oauth2Server do
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
    client_resource: Authx.Accounts.OauthClient,
    authorization_code_resource: Authx.Accounts.OauthAuthorizationCode,
    refresh_token_resource: Authx.Accounts.OauthRefreshToken,
    consent_resource: Authx.Accounts.OauthConsent,
    scopes: ["mcp"],
    # Dynamic client registration (RFC 7591). The library default is
    # `false` for safety; the installer turns it on because most
    # people setting up an OAuth server today need it for MCP-style
    # flows (ChatGPT Apps SDK, Claude.ai connectors, etc.). Set to
    # `false` if your auth server is for a fixed set of first-party
    # clients only.
    dcr_enabled?: true,
    # Client ID Metadata Documents — clients identify with an HTTPS
    # URL pointing at their metadata. This is the registration
    # mechanism the MCP spec (2026-07-28) recommends; DCR above is
    # kept for backwards compatibility. Set to `false` if your auth
    # server is for a fixed set of first-party clients only.
    cimd_enabled?: true,
    sign_in_path: "/sign-in"
end
