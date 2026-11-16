defmodule Authx.Accounts do
  use Ash.Domain, otp_app: :authx, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Authx.Accounts.User
    resource Authx.Accounts.Token
  end
end
