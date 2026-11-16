defmodule Authx.Oauth.Oidc.Server do
  @moduledoc """
  OpenID Connect (OIDC) authorization-server configuration.
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
    scopes: ["openid", "email"],
    # 客户端必须归属于某个 developer，而动态注册只能证明持有共享令牌，
    # 无法证明开发者身份；因此关闭 DCR 与 CIMD，客户端由开发者领域 action
    # （开发者控制台）创建。
    dcr_enabled?: false,
    cimd_enabled?: false,
    sign_in_path: "/sign-in"
end
