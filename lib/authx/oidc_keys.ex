defmodule Authx.OidcKeys do
  @moduledoc false
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def public_key, do: GenServer.call(__MODULE__, :public_key)
  def sign(claims), do: GenServer.call(__MODULE__, {:sign, claims})

  @impl true
  def init(nil) do
    key = JOSE.JWK.generate_key({:rsa, 2048})
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
