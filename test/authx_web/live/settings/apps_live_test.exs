defmodule AuthxWeb.Settings.AppsLiveTest do
  use AuthxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Ecto.Query
  import Authx.Fixtures

  require Ash.Query

  alias Authx.Audit.Event
  alias Authx.Oauth.Resources.Consent

  setup do
    developer = create_developer("live-consents-owner@example.com")

    client =
      register_client(developer, %{
        client_name: "Demo App",
        scope: "openid email profile"
      })

    user = create_user("live-consents-user@example.com", :user)
    consent = grant_consent(user, client, "openid email")

    %{client: client, consent: consent, user: user}
  end

  test "redirects to sign-in when the user is not authenticated" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/settings/apps")
  end

  test "lists the user's authorized applications and their scopes", %{
    user: user,
    consent: consent
  } do
    {:ok, view, _html} = live(signed_in_conn(user), ~p"/settings/apps")

    assert has_element?(view, "#applications-page")
    assert has_element?(view, "#consents-#{consent.id}", "Demo App")
    assert has_element?(view, "#consents-#{consent.id}", "openid email")
    assert has_element?(view, "#revoke-consent-#{consent.id}")
    refute has_element?(view, "#no-consents")
  end

  test "shows an empty state when nothing is authorized" do
    other = create_user("live-consents-empty@example.com", :user)

    {:ok, view, _html} = live(signed_in_conn(other), ~p"/settings/apps")
    assert has_element?(view, "#no-consents")
  end

  test "shows the client's last activity", %{user: user, client: client, consent: consent} do
    last_used_at = ~U[2026-11-18 10:24:00.000000Z]

    Authx.Repo.update_all(
      from(c in Authx.Oauth.Resources.Client, where: c.id == ^client.id),
      set: [last_used_at: last_used_at]
    )

    {:ok, view, _html} = live(signed_in_conn(user), ~p"/settings/apps")

    assert has_element?(view, "#consents-#{consent.id}", "2026-11-18 10:24 UTC")
  end

  test "revokes a consent after confirmation", %{user: user, consent: consent} do
    {:ok, view, _html} = live(signed_in_conn(user), ~p"/settings/apps")

    refute has_element?(view, "#revoke-dialog")

    view |> element("#revoke-consent-#{consent.id}") |> render_click()
    assert has_element?(view, "#revoke-dialog", "撤销对 Demo App 的授权？")

    view |> element("#revoke-cancel") |> render_click()
    refute has_element?(view, "#revoke-dialog")

    view |> element("#revoke-consent-#{consent.id}") |> render_click()
    html = view |> element("#revoke-confirm") |> render_click()

    assert html =~ "已撤销对 Demo App 的授权"
    refute has_element?(view, "#consents-#{consent.id}")
    assert has_element?(view, "#no-consents")

    assert {:ok, []} = Ash.read(Consent, authorize?: false)

    assert {:ok, [event]} = Ash.read(Event, authorize?: false)
    assert event.event == "consent.revoked"
    assert event.actor_user_id == user.id
    assert event.metadata["client_name"] == "Demo App"
  end

  test "cannot revoke another user's consent through a forged id", %{
    user: user,
    client: client
  } do
    other = create_user("live-consents-victim@example.com", :user)
    other_id = other.id
    other_consent = grant_consent(other, client, "openid")

    {:ok, view, _html} = live(signed_in_conn(user), ~p"/settings/apps")

    # Directly send an id the page never rendered.
    html = render_click(view, "select_revoke", %{"id" => other_consent.id})
    assert html =~ "不存在或已被撤销"
    refute has_element?(view, "#revoke-dialog")

    assert {:ok, [_still_there]} =
             Consent
             |> Ash.Query.filter(user_id == ^other_id)
             |> Ash.read(authorize?: false)
  end

  defp signed_in_conn(user), do: build_conn() |> sign_in_user(user)
end
