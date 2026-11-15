defmodule AuthxWeb.AuthRoutesTest do
  use AuthxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  for {name, path, action} <- [
        {"sign-in", "/sign-in", "/auth/user/password/sign_in"},
        {"registration", "/register", "/auth/user/password/register"},
        {"password reset request", "/reset", "/auth/user/password/reset_request"},
        {"password reset", "/password-reset/example-token", "/auth/user/password/reset"},
        {"confirmation", "/confirm_new_user/example-token", "/auth/user/confirm_new_user"},
        {"magic link", "/magic_link/example-token", "/auth/user/magic_link"}
      ] do
    test "#{name} page retains its form and uses the site banner", %{conn: conn} do
      {:ok, view, _html} = live(conn, unquote(path))

      assert has_element?(view, ".auth-card .auth-banner", "一处身份，多处连接。")
      refute has_element?(view, ".auth-banner img")
      refute has_element?(view, ".auth-card h2[class*='dark:text-white']")
      assert has_element?(view, "form[action='#{unquote(action)}']")
    end
  end

  test "sign-out page retains its confirmation form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-out")

    assert has_element?(view, ".auth-card form[action='/sign-out'] button[type='submit']")
  end
end
