defmodule AuthxWeb.OidcRouteGateTest do
  use AuthxWeb.ConnCase, async: false

  test "OIDC endpoints remain closed when not enabled" do
    old_demo = Application.get_env(:authx, :oauth2_demo_routes)
    old_local = Application.get_env(:authx, :local_oidc_enabled)
    Application.put_env(:authx, :oauth2_demo_routes, false)
    Application.put_env(:authx, :local_oidc_enabled, false)

    on_exit(fn ->
      Application.put_env(:authx, :oauth2_demo_routes, old_demo)
      Application.put_env(:authx, :local_oidc_enabled, old_local)
    end)

    assert build_conn() |> get("/.well-known/openid-configuration") |> response(404)
    assert build_conn() |> post("/oidc/token", %{}) |> response(404)
  end

  test "OIDC never publishes or exposes a client registration endpoint" do
    metadata = build_conn() |> get("/.well-known/openid-configuration") |> json_response(200)
    refute Map.has_key?(metadata, "registration_endpoint")

    assert :error =
             Phoenix.Router.route_info(AuthxWeb.Router, "POST", "/oidc/register", "localhost")
  end
end
