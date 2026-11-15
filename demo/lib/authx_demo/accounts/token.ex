defmodule AuthxDemo.Accounts.Token do
  use Ash.Resource,
    otp_app: :authx_demo,
    domain: AuthxDemo.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table("tokens")
    repo(AuthxDemo.Repo)
  end

  actions do
    defaults([:read])
  end
end
