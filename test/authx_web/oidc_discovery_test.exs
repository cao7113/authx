defmodule AuthxWeb.OidcDiscoveryTest do
  use AuthxWeb.ConnCase, async: false

  test "OIDC never publishes or exposes a client registration endpoint" do
    metadata = build_conn() |> get("/.well-known/openid-configuration") |> json_response(200)
    refute Map.has_key?(metadata, "registration_endpoint")

    assert :error =
             Phoenix.Router.route_info(AuthxWeb.Router, "POST", "/oidc/register", "localhost")
  end
end
