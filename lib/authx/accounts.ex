defmodule Authx.Accounts do
  use Ash.Domain, otp_app: :authx, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Authx.Accounts.Token
    resource Authx.Accounts.User
  end
end
