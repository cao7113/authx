defmodule AuthxWeb.OauthRoutesTest do
  use AuthxWeb.ConnCase, async: true

  alias AshAuthentication.Oauth2Server.Jwt
  alias Authx.Accounts.{OauthClient, User}
  alias Authx.Oauth2Server

  @redirect_uri "http://localhost:4001/auth/user/authx/callback"
  @verifier String.duplicate("a", 43)

  setup do
    client =
      OauthClient
      |> Ash.Changeset.for_create(:register, %{
        client_name: "Test client",
        redirect_uris: [@redirect_uri],
        grant_types: ["authorization_code"],
        response_types: ["code"],
        token_endpoint_auth_method: "none",
        scope: "mcp"
      })
      |> Ash.create!(authorize?: false)

    params = %{
      "client_id" => client.id,
      "redirect_uri" => @redirect_uri,
      "response_type" => "code",
      "scope" => "mcp",
      "state" => "test-state",
      "code_challenge" => Base.url_encode64(:crypto.hash(:sha256, @verifier), padding: false),
      "code_challenge_method" => "S256"
    }

    %{client: client, params: params}
  end

  test "an unauthenticated authorization request returns to sign in", %{
    conn: conn,
    params: params
  } do
    conn = get(conn, "/oauth/authorize", params)
    assert redirected_to(conn) =~ "/sign-in?"
    assert get_session(conn, :return_to) =~ "/oauth/authorize?"
  end

  test "signed-in authorization issues a single-use PKCE-bound access token", %{
    conn: conn,
    client: client,
    params: params
  } do
    user =
      User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "oauth-route@example.com",
        password: "a-secure-password",
        password_confirmation: "a-secure-password"
      })
      |> Ash.create!(authorize?: false)

    conn =
      conn
      |> init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)
      |> get("/oauth/authorize", params)

    html = conn |> html_response(200) |> LazyHTML.from_document()
    assert [consent_request] = LazyHTML.attribute(html["input[name='consent_request']"], "value")

    conn =
      conn
      |> recycle()
      |> post("/oauth/authorize", %{"consent_request" => consent_request, "action" => "approve"})

    callback = URI.parse(redirected_to(conn))

    assert "#{callback.scheme}://#{callback.host}:#{callback.port}#{callback.path}" ==
             @redirect_uri

    assert %{"code" => code, "state" => "test-state"} = URI.decode_query(callback.query)

    token_params = %{
      "grant_type" => "authorization_code",
      "client_id" => client.id,
      "redirect_uri" => @redirect_uri,
      "code" => code,
      "code_verifier" => @verifier
    }

    invalid =
      build_conn()
      |> post("/oauth/token", Map.put(token_params, "code_verifier", String.duplicate("b", 43)))

    assert %{"error" => "invalid_grant"} = json_response(invalid, 400)

    result = build_conn() |> post("/oauth/token", token_params) |> json_response(200)
    assert %{"access_token" => access_token, "token_type" => "Bearer"} = result
    assert {:ok, %{"sub" => subject, "scope" => "mcp"}} = Jwt.verify(Oauth2Server, access_token)
    assert subject == user.id

    replay = build_conn() |> post("/oauth/token", token_params)
    assert %{"error" => "invalid_grant"} = json_response(replay, 400)
  end

  test "denied consent returns an error without issuing a code", %{conn: conn, params: params} do
    user =
      User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "oauth-deny@example.com",
        password: "a-secure-password",
        password_confirmation: "a-secure-password"
      })
      |> Ash.create!(authorize?: false)

    conn =
      conn
      |> init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)
      |> get("/oauth/authorize", params)

    html = conn |> html_response(200) |> LazyHTML.from_document()
    assert [consent_request] = LazyHTML.attribute(html["input[name='consent_request']"], "value")

    conn =
      conn
      |> recycle()
      |> post("/oauth/authorize", %{"consent_request" => consent_request, "action" => "deny"})

    assert %{"error" => "access_denied", "state" => "test-state"} =
             conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end

  test "an unregistered redirect URI is not followed", %{conn: conn, params: params} do
    conn =
      get(
        conn,
        "/oauth/authorize",
        Map.put(params, "redirect_uri", "http://localhost:4001/wrong")
      )

    assert html_response(conn, 400)
    assert get_resp_header(conn, "location") == []
  end

  test "legacy OIDC alias and dynamic registration are not exposed", %{conn: conn} do
    assert conn |> get("/oauth/openid-configuration") |> response(404) == ""
    assert build_conn() |> post("/oauth/register", %{}) |> response(404) == ""
  end
end
