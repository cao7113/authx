defmodule AuthxWeb.PageControllerTest do
  use AuthxWeb.ConnCase

  test "home displays navigation and sign-in entry points", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.attribute(html["#site-home-link"], "href") == ["/"]
    assert LazyHTML.attribute(html["#nav-sign-in"], "href") == ["/sign-in"]
    assert LazyHTML.attribute(html["#nav-register"], "href") == ["/register"]
    assert LazyHTML.attribute(html["#home-sign-in"], "href") == ["/sign-in"]
    assert Enum.count(html["#about"]) == 1
  end

  test "navigation offers sign out to signed-in users", %{conn: conn} do
    user =
      Authx.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "home@example.com",
        password: "a-secure-password",
        password_confirmation: "a-secure-password"
      })
      |> Ash.create!(authorize?: false)

    html =
      conn
      |> init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)
      |> get(~p"/")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert LazyHTML.text(html["#nav-user-email"]) == "home@example.com"
    assert Enum.empty?(html["#nav-user-role"])
    assert LazyHTML.attribute(html["#user-menu-toggle"], "aria-controls") == ["user-menu-options"]
    assert LazyHTML.attribute(html["#user-menu-options #nav-sign-out"], "href") == ["/sign-out"]
    assert LazyHTML.attribute(html["#home-sign-out"], "href") == ["/sign-out"]
    assert Enum.empty?(html["#nav-sign-in"])
    assert Enum.empty?(html["#nav-register"])
  end

  test "authentication pages share the site navigation", %{conn: conn} do
    html = conn |> get(~p"/sign-in") |> html_response(200) |> LazyHTML.from_document()

    assert LazyHTML.attribute(html["#site-home-link"], "href") == ["/"]
    assert LazyHTML.attribute(html["#nav-register"], "href") == ["/register"]
  end
end
