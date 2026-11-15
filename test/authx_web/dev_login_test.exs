defmodule AuthxWeb.DevLoginTest do
  use AuthxWeb.ConnCase, async: false

  setup do
    original_routes = Application.fetch_env(:authx, :dev_routes)
    original_defaults = Application.fetch_env(:authx, :dev_login_defaults)

    on_exit(fn ->
      restore_env(:dev_routes, original_routes)
      restore_env(:dev_login_defaults, original_defaults)
    end)

    :ok
  end

  test "only exposes default credentials when development routes are enabled", %{conn: conn} do
    Application.put_env(:authx, :dev_login_defaults, %{
      email: "admin@l.h",
      password: "password123456"
    })

    Application.put_env(:authx, :dev_routes, true)
    html = conn |> get(~p"/sign-in") |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.attribute(html["body"], "data-dev-login-email") == ["admin@l.h"]
    assert LazyHTML.attribute(html["body"], "data-dev-login-password") == ["password123456"]

    Application.put_env(:authx, :dev_routes, false)
    html = conn |> get(~p"/sign-in") |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.attribute(html["body"], "data-dev-login-email") == []
    assert LazyHTML.attribute(html["body"], "data-dev-login-password") == []
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:authx, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:authx, key)
end
