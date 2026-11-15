defmodule AuthxWeb.AuthRoutesTest do
  use AuthxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "sign-in page renders the password form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    assert has_element?(view, "form[action='/auth/user/password/sign_in']")
  end

  test "registration page renders the password form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    assert has_element?(view, "form[action='/auth/user/password/register']")
  end
end
