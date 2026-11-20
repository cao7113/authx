defmodule AuthxWeb.AuthRoutesTest do
  use AuthxWeb.ConnCase, async: true

  alias Authx.Accounts.User

  import Phoenix.LiveViewTest

  for {name, path, action} <- [
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

  test "sign-in page posts directly to the authentication controller", %{conn: conn} do
    html = conn |> get(~p"/sign-in") |> html_response(200) |> LazyHTML.from_document()

    assert ["/auth/user/password/sign_in"] = LazyHTML.attribute(html["#sign-in-form"], "action")
    assert ["post"] = LazyHTML.attribute(html["#sign-in-form"], "method")
    assert ["sign-in-submit"] = LazyHTML.attribute(html["#sign-in-submit"], "id")
    assert html[".auth-card .auth-banner"] |> LazyHTML.text() =~ "欢迎回来"
    assert ["/reset"] = LazyHTML.attribute(html["#password-reset-link"], "href")

    assert ["/auth/user/magic_link/request"] =
             LazyHTML.attribute(html["#magic-link-request-form"], "action")
  end

  test "registration page posts directly to the authentication controller", %{conn: conn} do
    html = conn |> get(~p"/register") |> html_response(200) |> LazyHTML.from_document()

    assert ["/auth/user/password/register"] =
             LazyHTML.attribute(html["#register-form"], "action")

    assert ["register-submit"] = LazyHTML.attribute(html["#register-submit"], "id")
  end

  test "unconfirmed registration redirects to the confirmation page", %{conn: conn} do
    email = "register-confirm-#{System.unique_integer([:positive])}@example.com"

    conn =
      post(conn, "/auth/user/password/register", %{
        "user" => %{
          "email" => email,
          "password" => "a-secure-password",
          "password_confirmation" => "a-secure-password"
        }
      })

    assert redirected_to(conn) == "/auth/please-confirm"
  end

  test "please confirm page offers confirmation resend", %{conn: conn} do
    user =
      Ash.Seed.seed!(User, %{
        email: "pending-confirmation@example.com",
        hashed_password: "not-a-real-hash",
        confirmed_at: nil
      })

    html =
      conn
      |> init_test_session(
        pending_confirmation: %{
          user_id: user.id,
          email: to_string(user.email),
          created_at: System.system_time(:second)
        }
      )
      |> get(~p"/auth/please-confirm")
      |> html_response(200)
      |> LazyHTML.from_document()

    assert ["/auth/please-confirm/resend"] =
             LazyHTML.attribute(html["#resend-confirmation-form"], "action")

    assert ["resend-confirmation-submit"] =
             LazyHTML.attribute(html["#resend-confirmation-submit"], "id")
  end

  test "please confirm redirects without a pending session", %{conn: conn} do
    conn = get(conn, ~p"/auth/please-confirm")

    assert redirected_to(conn) == "/sign-in"
  end

  test "sign-out page retains its confirmation form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-out")

    assert has_element?(view, ".auth-card form[action='/sign-out'] button[type='submit']")
  end
end
