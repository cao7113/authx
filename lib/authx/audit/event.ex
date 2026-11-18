defmodule Authx.Audit.Event do
  @moduledoc """
  One append-only audit event.

  The table is intentionally generic: `event` names the action, `target_*`
  identifies what it happened to, and `metadata` carries a small snapshot
  needed to read the event later (for example a client name at revocation
  time). Do not store tokens, authorization codes, passwords, or request
  headers here.
  """

  use Ash.Resource,
    otp_app: :authx,
    domain: Authx.Audit,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAdmin.Resource]

  admin do
    table_columns [
      :event,
      :actor_user_id,
      :subject_user_id,
      :target_type,
      :target_id,
      :inserted_at
    ]
  end

  postgres do
    table "audit_events"
    repo Authx.Repo
  end

  actions do
    defaults [:read]

    create :record do
      description "Internal system write. Only domain functions call this."

      accept [
        :event,
        :actor_user_id,
        :subject_user_id,
        :target_type,
        :target_id,
        :metadata
      ]
    end
  end

  policies do
    # Audit events are append-only and only administrators may read them.
    # There is deliberately no create policy: user-facing actor writes are
    # denied. `Authx.Audit.record/1` is the internal write path.
    policy action_type(:read) do
      authorize_if Authx.Accounts.Checks.AdminCheck
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :event, :string do
      allow_nil? false
      public? true
      description ~s(Stable dotted event name, for example "consent.revoked".)
    end

    attribute :actor_user_id, :uuid do
      public? true
      description "The user who performed the action, when there is one."
    end

    attribute :subject_user_id, :uuid do
      public? true
      description "The user affected by the action, for user-scoped events."
    end

    attribute :target_type, :string do
      public? true
      description ~s(Kind of target, for example "oauth_client".)
    end

    attribute :target_id, :uuid do
      public? true
    end

    attribute :metadata, :map do
      allow_nil? false
      default %{}
      public? true
      description "Small, non-sensitive snapshot of the event."
    end

    create_timestamp :inserted_at
  end
end
