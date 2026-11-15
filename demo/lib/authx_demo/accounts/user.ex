defmodule AuthxDemo.Accounts.User do
  use Ash.Resource,
    otp_app: :authx_demo,
    domain: AuthxDemo.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication]

  postgres do
    table("users")
    repo(AuthxDemo.Repo)
  end

  authentication do
    tokens do
      enabled?(true)
      token_resource(AuthxDemo.Accounts.Token)
      signing_secret(AuthxDemo.Secrets)
      store_all_tokens?(true)
      require_token_presence_for_authentication?(true)
    end

    strategies do
      oidc :authx do
        client_id(AuthxDemo.Secrets)
        base_url(AuthxDemo.Secrets)
        redirect_uri(AuthxDemo.Secrets)
        client_authentication_method("none")
        code_verifier(true)
        nonce(true)
        trust_email_verified?(true)
        authorization_params(scope: "email")
        # The user resource stores the issuer/subject identity directly.
        warn_on_missing_identity_resource?(false)
      end
    end
  end

  actions do
    defaults([:read])

    read :get_by_subject do
      argument(:subject, :string, allow_nil?: false)
      get?(true)
      prepare(AshAuthentication.Preparations.FilterBySubject)
    end

    create :register_with_authx do
      argument(:user_info, :map, allow_nil?: false)
      argument(:oauth_tokens, :map, allow_nil?: false, sensitive?: true)
      upsert?(true)
      upsert_identity(:external_identity)
      upsert_fields([:email])

      change(AshAuthentication.GenerateTokenChange)
      change(AuthxDemo.Accounts.Changes.StoreOidcIdentity)
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:issuer, :string, allow_nil?: false, public?: true)
    attribute(:subject, :string, allow_nil?: false, public?: true)
    attribute(:email, :string, allow_nil?: false, public?: true)
  end

  identities do
    identity(:external_identity, [:issuer, :subject])
  end
end
