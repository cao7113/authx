defmodule Authx.Oauth.Domain do
  use Ash.Domain, otp_app: :authx, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Authx.Oauth.Resources.Client
    resource Authx.Oauth.Resources.Consent
    resource Authx.Oauth.Resources.AuthorizationCode
    resource Authx.Oauth.Resources.RefreshToken
  end
end
