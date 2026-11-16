defmodule Authx.Oauth.Oidc.Keys do
  @moduledoc """
  Manages RS256 signing keys and public key distribution for OIDC tokens.
  """
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def public_key, do: GenServer.call(__MODULE__, :public_key)
  def sign(claims), do: GenServer.call(__MODULE__, {:sign, claims})

  @impl true
  def init(nil) do
    key =
      case Application.get_env(:authx, :oidc_private_key_file) do
        nil ->
          JOSE.JWK.generate_key({:rsa, 2048})

        path ->
          key = path |> File.read!() |> JOSE.JWK.from_pem()
          {_, params} = JOSE.JWK.to_map(key)

          unless params["kty"] == "RSA" and is_binary(params["d"]) do
            raise "OIDC private key must be an RSA private key"
          end

          key
      end

    kid = JOSE.JWK.thumbprint(key)
    {_, public} = key |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()

    {:ok,
     %{
       key: key,
       kid: kid,
       public: Map.merge(public, %{"kid" => kid, "use" => "sig", "alg" => "RS256"})
     }}
  end

  @impl true
  def handle_call(:public_key, _from, state), do: {:reply, state.public, state}

  def handle_call({:sign, claims}, _from, state) do
    {_, token} =
      JOSE.JWT.sign(state.key, %{"alg" => "RS256", "kid" => state.kid}, claims)
      |> JOSE.JWS.compact()

    {:reply, token, state}
  end
end
