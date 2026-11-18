defmodule Authx.Developers.Developer do
  use Ash.Resource,
    otp_app: :authx,
    domain: Authx.Developers,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAdmin.Resource]

  admin do
    label_field :id
    show_calculations [:user_email]
    table_columns [:id, :status, :user_email, :granted_at, :granted_by_email]
  end

  postgres do
    table "developers"
    repo Authx.Repo
  end

  actions do
    defaults [:read]

    create :grant do
      description "Grant developer status to an existing Authx user by email (default) or user_id. Admin only."
      accept []
      argument :email, :ci_string, allow_nil?: true
      argument :user_id, :uuid, allow_nil?: true

      change Authx.Developers.Changes.ResolveUserForGrant
    end

    read :get_by_user_id do
      description "Look up a developer record by user ID."
      argument :user_id, :uuid, allow_nil?: false
      get? true
      filter expr(user_id == ^arg(:user_id))
    end

    read :get_by_user_email do
      description "Look up a developer record by the associated user email."
      argument :email, :ci_string, allow_nil?: false
      get? true
      filter expr(user.email == ^arg(:email))
    end

    # 撤销/停用（revoke / suspend）功能待客户端级联影响与停用语义明确后实现
  end

  policies do
    # 仅具有系统管理员角色（admin）的 actor 可以执行授予操作
    policy action(:grant) do
      authorize_if Authx.Accounts.Checks.AdminCheck
    end

    # 管理员可以查看任意 developer 记录；用户自身也可以查看自己的 developer 记录
    policy action([:read, :get_by_user_id, :get_by_user_email]) do
      authorize_if Authx.Accounts.Checks.AdminCheck
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :active
      constraints one_of: [:active, :suspended]
      description "Status of developer access. Currently default to active."
    end

    attribute :granted_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      description "Timestamp when the developer role was granted."
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Authx.Accounts.User do
      allow_nil? false
      attribute_writable? true
      primary_key? false
    end

    belongs_to :granted_by, Authx.Accounts.User do
      source_attribute :granted_by_user_id
      allow_nil? false
      attribute_writable? true
      primary_key? false
    end
  end

  calculations do
    calculate :user_email, :ci_string, expr(user.email)
    calculate :granted_by_email, :ci_string, expr(granted_by.email)
  end

  identities do
    identity :unique_user, [:user_id]
  end
end
