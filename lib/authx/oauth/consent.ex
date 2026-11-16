defmodule Authx.Oauth.Consent do
  use Ash.Resource,
    otp_app: :authx,
    domain: Authx.Oauth,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "oauth_consents"
    repo Authx.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :grant do
      upsert? true
      upsert_identity :by_user_client
      accept [:user_id, :client_id, :scope]
      change set_attribute(:granted_at, &DateTime.utc_now/0)
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :client_id, :uuid_v7 do
      allow_nil? false
      public? true
    end

    attribute :scope, :string do
      allow_nil? false
      public? true
    end

    attribute :granted_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end
  end

  relationships do
    belongs_to :user, Authx.Accounts.User do
      allow_nil? false
      attribute_writable? true
    end

    belongs_to :client, Authx.Oauth.Client do
      source_attribute :client_id
      allow_nil? false
      attribute_writable? true
    end
  end

  identities do
    identity :by_user_client, [:user_id, :client_id]
  end
end
