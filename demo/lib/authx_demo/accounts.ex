defmodule AuthxDemo.Accounts do
  use Ash.Domain, otp_app: :authx_demo

  resources do
    resource(AuthxDemo.Accounts.User)
    resource(AuthxDemo.Accounts.Token)
  end
end
