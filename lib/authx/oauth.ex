defmodule Authx.Oauth do
  use Ash.Domain, otp_app: :authx, extensions: [AshAdmin.Domain]

  alias Authx.Oauth.Client

  admin do
    show? true
  end

  resources do
    resource Authx.Oauth.Client
    resource Authx.Oauth.Consent
    resource Authx.Oauth.AuthorizationCode
    resource Authx.Oauth.RefreshToken
  end

  @doc """
  Registers a client owned by `developer`.

  The given developer is passed to Ash as the actor and is the only source of
  ownership; any `:actor` in `opts` is overridden and ownership can never be
  supplied as input.
  """
  def register_client(developer, attrs, opts \\ []) do
    opts = Keyword.put(opts, :actor, developer)

    Client
    |> Ash.Changeset.for_create(:register, attrs, opts)
    |> Ash.create(opts)
  end
end
