defmodule Authx.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Authx.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:authx, :token_signing_secret)
  end
end
