defmodule AuthxWeb.AdminAccessTest do
  use AuthxWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Authx.Accounts.{Admins, User}

  test "only administrators see and access management tools", %{conn: conn} do
    admin = create_user("admin-access@example.com")
    member = create_user("member-access@example.com")
    assert {:ok, _} = Admins.bootstrap(to_string(admin.email))

    for path <- ["/admin", "/admin/dashboard", "/admin/dashboard/home", "/oban", "/manage/users"] do
      assert redirected_to(get(conn, path)) == "/"
      assert redirected_to(get(signed_in_conn(member), path)) == "/"
    end

    guest = conn |> get("/") |> html_response(200) |> LazyHTML.from_document()

    member_home =
      member |> signed_in_conn() |> get("/") |> html_response(200) |> LazyHTML.from_document()

    admin_home =
      admin |> signed_in_conn() |> get("/") |> html_response(200) |> LazyHTML.from_document()

    assert Enum.empty?(guest["#admin-tools"])
    assert Enum.empty?(member_home["#admin-tools"])
    assert LazyHTML.attribute(admin_home["#admin-users-link"], "href") == ["/manage/users"]
    assert LazyHTML.attribute(admin_home["#admin-dashboard-link"], "href") == ["/admin"]
    assert LazyHTML.attribute(admin_home["#live-dashboard-link"], "href") == ["/admin/dashboard"]
    assert LazyHTML.attribute(admin_home["#oban-dashboard-link"], "href") == ["/oban"]
    assert LazyHTML.text(admin_home["#nav-user-email"]) == "admin-access@example.com"
    assert String.trim(LazyHTML.text(admin_home["#nav-user-role"])) == "(admin)"

    assert LazyHTML.attribute(admin_home["#user-menu-options #nav-sign-out"], "href") == [
             "/sign-out"
           ]

    assert {:ok, _view, _html} = live(signed_in_conn(admin), "/admin")
    assert {:ok, _view, _html} = live(signed_in_conn(admin), "/admin/dashboard/home")
    assert {:ok, _view, _html} = live(signed_in_conn(admin), "/manage/users")
  end

  test "role management works and revoking access closes active sessions" do
    admin = create_user("admin-manager@example.com")
    member = create_user("member-manager@example.com")
    assert {:ok, _} = Admins.bootstrap(to_string(admin.email))
    {:ok, view, _html} = live(signed_in_conn(admin), "/manage/users")

    view
    |> form("#admin-user-search", search: %{email: to_string(member.email)})
    |> render_submit()

    assert has_element?(view, "#admin-selected-user")
    view |> element("#admin-toggle-role") |> render_click()
    assert Admins.admin?(member.id)

    {:ok, member_view, _html} = live(signed_in_conn(member), "/manage/users")
    assert {:ok, _} = Admins.set_role(admin.id, member.id, :user)
    assert_redirect(member_view, "/")
  end

  test "dashboard sessions close on role revocation and sign out" do
    conf = %{Oban.config() | testing: :disabled}
    start_supervised!({Oban.Sonar, conf: conf, name: Oban.Registry.via(Oban, Oban.Sonar)})
    start_supervised!({Oban.Met, conf: Oban.config()})

    admin = create_user("admin-dashboard@example.com")
    member = create_user("member-dashboard@example.com")
    assert {:ok, _} = Admins.bootstrap(to_string(admin.email))
    assert {:ok, _} = Admins.set_role(admin.id, member.id, :admin)

    {:ok, ash_view, _html} = live(signed_in_conn(member), "/admin")
    {:ok, oban_view, _html} = live(signed_in_conn(member), "/oban")
    {:ok, dashboard_view, _html} = live(signed_in_conn(member), "/admin/dashboard/home")
    assert {:ok, _} = Admins.set_role(admin.id, member.id, :user)
    assert_redirect(ash_view, "/")
    assert_redirect(oban_view, "/")
    assert_redirect(dashboard_view, "/")

    conn = signed_in_conn(admin)
    {:ok, ash_view, _html} = live(conn, "/admin")
    {:ok, oban_view, _html} = live(conn, "/oban")
    {:ok, dashboard_view, _html} = live(conn, "/admin/dashboard/home")
    assert redirected_to(delete(conn, "/sign-out")) == "/"
    assert_redirect(ash_view, "/")
    assert_redirect(oban_view, "/")
    assert_redirect(dashboard_view, "/")
  end

  test "dev menu is gated by development routes" do
    html =
      (&AuthxWeb.Layouts.site_header/1)
      |> render_component(%{current_user: nil, dev_routes_enabled: true})
      |> LazyHTML.from_fragment()

    assert LazyHTML.attribute(html["#dev-tools-toggle"], "aria-controls") == ["dev-tools-menu"]

    assert LazyHTML.attribute(html["#dev-tools-menu a"], "href") == ["/dev/mailbox"]

    html =
      (&AuthxWeb.Layouts.site_header/1)
      |> render_component(%{current_user: nil, dev_routes_enabled: false})
      |> LazyHTML.from_fragment()

    assert Enum.empty?(html["#dev-tools"])
  end

  defp create_user(email) do
    {:ok, password} = AshAuthentication.BcryptProvider.hash("password123456")

    Ash.Seed.seed!(User, %{
      email: email,
      hashed_password: password,
      confirmed_at: DateTime.utc_now()
    })
  end

  defp signed_in_conn(user) do
    strategy = AshAuthentication.Info.strategy!(User, :password)

    {:ok, authenticated} =
      AshAuthentication.Strategy.action(
        strategy,
        :sign_in,
        %{email: user.email, password: "password123456"},
        []
      )

    build_conn()
    |> init_test_session(%{})
    |> AshAuthentication.Plug.Helpers.store_in_session(authenticated)
  end
end
