defmodule Authx.Accounts do
  use Ash.Domain, otp_app: :authx, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Authx.Accounts.Token
    resource Authx.Accounts.User
    resource Authx.Accounts.OauthClient
    resource Authx.Accounts.OauthAuthorizationCode
    resource Authx.Accounts.OauthRefreshToken
    resource Authx.Accounts.OauthConsent
  end
end
