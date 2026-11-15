defmodule AuthxDemo.Secrets do
  use AshAuthentication.Secret

  def secret_for([:authentication, :tokens, :signing_secret], _, _, _) do
    Application.fetch_env(:authx_demo, :token_signing_secret)
  end

  def secret_for([:authentication, :strategies, :authx, key], _, _, _)
      when key in [:client_id, :base_url, :redirect_uri] do
    config_key =
      case key do
        :client_id -> :oidc_client_id
        :base_url -> :oidc_issuer
        :redirect_uri -> :oidc_redirect_uri
      end

    case Application.fetch_env(:authx_demo, config_key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, "Missing #{config_key} configuration"}
    end
  end
end
