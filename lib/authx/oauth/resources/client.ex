defmodule Authx.Oauth.Resources.Client do
  use Ash.Resource,
    otp_app: :authx,
    domain: Authx.Oauth.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.Oauth2Server.ClientResource, AshAdmin.Resource],
    authorizers: [Ash.Policy.Authorizer]

  admin do
    table_columns [:client_name, :redirect_uris, :scope, :last_used_at, :updated_at]
  end

  postgres do
    table "oauth_clients"
    repo Authx.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      description """
      Registers a client owned by the acting developer.

      The owner is always taken from the actor; it is never accepted as input.
      """

      accept [
        :client_name,
        :redirect_uris,
        :grant_types,
        :response_types,
        :token_endpoint_auth_method,
        :scope
      ]

      # 安全关键项在资源层校验，所有入口（控制台、mix task、未来 API）共用。
      validate Authx.Oauth.Validations.RedirectUris
      validate one_of(:token_endpoint_auth_method, ["none"])

      change Authx.Oauth.Changes.AssignDeveloperOwner
    end

    update :update do
      description """
      Updates a client owned by the acting developer.

      The owner is never accepted as input; only the owning developer can
      update the client.
      """

      require_atomic? false

      accept [
        :client_name,
        :redirect_uris,
        :grant_types,
        :response_types,
        :token_endpoint_auth_method,
        :scope
      ]

      validate Authx.Oauth.Validations.RedirectUris
      validate one_of(:token_endpoint_auth_method, ["none"])
    end

    # CIMD 注册会为任意 URL 隐式创建客户端，无法确定开发者归属，因此在
    # 归属模型下不提供。启用 CIMD 前必须先定义其所有权语义。
  end

  policies do
    # OIDC/OAuth 协议交互（授权、令牌、UserInfo）通过认证上下文执行，
    # 不经过开发者控制台；它们的授权由协议校验与资源本身的属性决定。
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # 只有当前有效的开发者本人（actor 即该 Developer 记录）能读取自己名下的
    # 客户端；其他开发者、普通用户和匿名访问者都看不到。
    policy action_type(:read) do
      forbid_unless Authx.Developers.Checks.ActiveDeveloper
      authorize_if relates_to_actor_via(:developer)
    end

    # 客户端只能由当前有效的开发者创建，归属由 actor 决定。
    policy action(:register) do
      authorize_if Authx.Developers.Checks.ActiveDeveloper
    end

    # 只有当前有效且是该客户端属主的开发者可以更新。
    policy action(:update) do
      forbid_unless Authx.Developers.Checks.ActiveDeveloper
      authorize_if relates_to_actor_via(:developer)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :client_name, :string do
      allow_nil? false
      public? true
    end

    attribute :redirect_uris, {:array, :string} do
      allow_nil? false
      public? true
    end

    attribute :grant_types, {:array, :string} do
      public? true
    end

    attribute :response_types, {:array, :string} do
      public? true
    end

    attribute :token_endpoint_auth_method, :string do
      public? true
    end

    attribute :scope, :string do
      public? true
    end

    attribute :last_used_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :developer, Authx.Developers.Developer do
      description "The developer that owns this client. Exactly one owner per client."
      allow_nil? false
      attribute_writable? false
      primary_key? false
    end
  end
end
