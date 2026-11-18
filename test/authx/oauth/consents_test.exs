defmodule Authx.Oauth.ConsentsTest do
  use Authx.DataCase, async: false

  require Ash.Query

  import Authx.Fixtures

  alias Authx.Audit.Event
  alias Authx.Oauth.Consents
  alias Authx.Oauth.Resources.Consent

  setup do
    developer = create_developer("consents-owner@example.com")
    client = register_client(developer, %{client_name: "Consent test"})
    user = create_user("consent-user@example.com", :user)

    %{client: client, user: user}
  end

  describe "listing" do
    test "lists only the user's own consents with the client loaded", %{
      client: client,
      user: user
    } do
      other = create_user("consent-other@example.com", :user)
      grant_consent(user, client, "openid email")
      grant_consent(other, client, "openid")

      assert [consent] = Consents.list_for_user(user)
      assert consent.client_id == client.id
      assert consent.client.client_name == "Consent test"
      assert consent.scope == "openid email"
    end

    test "returns an empty list when the user has not authorized anything", %{user: user} do
      assert [] = Consents.list_for_user(user)
    end
  end

  describe "fetching" do
    test "fetches the user's own consent by id", %{client: client, user: user} do
      consent = grant_consent(user, client)

      assert {:ok, found} = Consents.fetch_for_user(user, consent.id)
      assert found.id == consent.id
      assert found.client.client_name == "Consent test"
    end

    test "another user's consent is indistinguishable from a missing one", %{
      client: client,
      user: user
    } do
      other = create_user("consent-thief@example.com", :user)
      consent = grant_consent(user, client)

      assert {:error, :not_found} = Consents.fetch_for_user(other, consent.id)
      assert {:error, :not_found} = Consents.fetch_for_user(user, Ecto.UUID.generate())
      assert {:error, :not_found} = Consents.fetch_for_user(user, "not-a-uuid")
    end
  end

  describe "revoking" do
    test "deletes the consent and records an audit event", %{client: client, user: user} do
      consent = grant_consent(user, client, "openid email")

      assert {:ok, revoked} = Consents.revoke(user, consent)
      assert revoked.id == consent.id

      assert [] = Consents.list_for_user(user)
      assert {:error, :not_found} = Consents.fetch_for_user(user, consent.id)

      assert [event] = audit_events()
      assert event.event == "consent.revoked"
      assert event.actor_user_id == user.id
      assert event.subject_user_id == user.id
      assert event.target_type == "oauth_client"
      assert event.target_id == client.id
      assert event.metadata == %{"client_name" => "Consent test", "scope" => "openid email"}
    end

    test "revoking an already revoked consent returns not found and writes no event", %{
      client: client,
      user: user
    } do
      consent = grant_consent(user, client)

      assert {:ok, _revoked} = Consents.revoke(user, consent)
      assert {:error, :not_found} = Consents.revoke(user, consent)

      assert [_one] = audit_events()
    end

    test "only the owning user can revoke at the resource layer", %{client: client, user: user} do
      other = create_user("consent-other-revoke@example.com", :user)
      consent = grant_consent(user, client)

      assert {:error, error} = Ash.destroy(consent, actor: other)
      assert %Ash.Error.Forbidden{} = Ash.Error.to_error_class(error)

      assert {:ok, [_consent]} =
               Consent
               |> Ash.Query.filter(user_id == ^user.id)
               |> Ash.read(authorize?: false)
    end
  end

  describe "consent read policy" do
    test "a user cannot read another user's consent directly", %{client: client, user: user} do
      other = create_user("consent-reader@example.com", :user)
      grant_consent(user, client)

      assert {:ok, []} =
               Consent
               |> Ash.Query.filter(user_id == ^user.id)
               |> Ash.read(actor: other)
    end
  end

  defp audit_events do
    Event
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!(authorize?: false)
  end
end
