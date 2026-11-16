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

  def secret_for([:issuer_url], Authx.Oauth.Server, _opts, _context) do
    Application.fetch_env(:authx, :oauth2_issuer_url)
  end

  def secret_for([:resource_url], Authx.Oauth.Server, _opts, _context) do
    Application.fetch_env(:authx, :oauth2_resource_url)
  end

  def secret_for([:signing_secret], Authx.Oauth.Server, _opts, _context) do
    Application.fetch_env(:authx, :oauth2_signing_secret)
  end

  def secret_for([:issuer_url], Authx.Oauth.Oidc.Server, _opts, _context) do
    Application.fetch_env(:authx, :oauth2_issuer_url)
  end

  def secret_for([:resource_url], Authx.Oauth.Oidc.Server, _opts, _context) do
    Application.fetch_env(:authx, :oidc_resource_url)
  end

  def secret_for([:signing_secret], Authx.Oauth.Oidc.Server, _opts, _context) do
    Application.fetch_env(:authx, :oauth2_signing_secret)
  end
end
