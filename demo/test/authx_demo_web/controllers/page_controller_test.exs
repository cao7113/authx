defmodule AuthxDemoWeb.PageControllerTest do
  use AuthxDemoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = conn |> html_response(200) |> LazyHTML.from_document()
    assert LazyHTML.attribute(html["#authx-sign-in"], "href") == ["/auth/user/authx"]
  end
end
