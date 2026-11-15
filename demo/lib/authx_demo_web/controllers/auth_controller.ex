defmodule AuthxDemoWeb.AuthController do
  use AuthxDemoWeb, :controller
  use AshAuthentication.Phoenix.Controller

  def success(conn, _activity, user, _token) do
    conn
    |> configure_session(renew: true)
    |> store_in_session(user)
    |> put_flash(:info, "Signed in with Authx")
    |> redirect(to: ~p"/")
  end

  def failure(conn, _activity, _reason) do
    require Logger
    Logger.warning("OIDC sign-in failed")

    conn
    |> put_flash(:error, "Authx sign-in failed")
    |> redirect(to: ~p"/")
  end

  def sign_out(conn, _) do
    conn
    |> clear_session(:authx_demo)
    |> configure_session(renew: true)
    |> redirect(to: ~p"/")
  end
end
