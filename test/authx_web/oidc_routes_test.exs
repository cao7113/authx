defmodule AuthxWeb.OidcRoutesTest do
  use AuthxWeb.ConnCase, async: true

  import Authx.Fixtures

  alias Authx.Accounts.User

  @redirect_uri "http://localhost:4001/auth/user/authx/callback"
  @verifier String.duplicate("v", 43)

  setup do
    developer = create_developer("oidc-routes@example.com")

    client =
      register_client(developer, %{
        client_name: "OIDC test",
        scope: "openid email profile"
      })

    user =
      User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "oidc-test@example.com",
        password: "a-secure-password",
        password_confirmation: "a-secure-password"
      })
      |> Ash.create!(authorize?: false)

    %{client: client, user: user}
  end

  test "discovery publishes a public verification key and real endpoints" do
    metadata = build_conn() |> get("/.well-known/openid-configuration") |> json_response(200)
    assert metadata["issuer"] == "http://localhost:4000"
    assert metadata["authorization_endpoint"] == "http://localhost:4000/oidc/authorize"
    assert metadata["token_endpoint"] == "http://localhost:4000/oidc/token"
    assert metadata["id_token_signing_alg_values_supported"] == ["RS256"]

    # 客户端由开发者创建并归属某个 developer，不发布注册端点
    refute Map.has_key?(metadata, "registration_endpoint")

    assert %{"keys" => [%{"kty" => "RSA", "kid" => _, "n" => _, "e" => _} = key]} =
             build_conn() |> get("/oidc/jwks") |> json_response(200)

    refute Map.has_key?(key, "d")
  end

  test "OIDC code binds nonce, client and PKCE; userinfo returns the same identity", %{
    client: client,
    user: user
  } do
    code = authorize(client, user, "openid email profile", "nonce-1")
    params = token_params(client, code)

    invalid =
      build_conn()
      |> post("/oidc/token", Map.put(params, "code_verifier", String.duplicate("x", 43)))

    assert %{"error" => "invalid_grant"} = json_response(invalid, 400)

    result = build_conn() |> post("/oidc/token", params) |> json_response(200)
    assert %{"access_token" => access_token, "id_token" => id_token} = result
    %{"keys" => [public]} = build_conn() |> get("/oidc/jwks") |> json_response(200)
    assert {true, jwt, _} = JOSE.JWT.verify_strict(JOSE.JWK.from_map(public), ["RS256"], id_token)
    assert jwt.fields["iss"] == "http://localhost:4000"
    assert jwt.fields["aud"] == client.id
    assert jwt.fields["sub"] == user.id
    assert jwt.fields["nonce"] == "nonce-1"
    assert jwt.fields["email"] == "oidc-test@example.com"
    assert jwt.fields["email_verified"] == false
    assert jwt.fields["updated_at"] == DateTime.to_unix(user.updated_at)

    info =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> access_token)
      |> get("/oidc/userinfo")
      |> json_response(200)

    assert info == %{
             "sub" => user.id,
             "email" => "oidc-test@example.com",
             "email_verified" => false,
             "updated_at" => DateTime.to_unix(user.updated_at)
           }

    assert %{"error" => "invalid_grant"} =
             build_conn() |> post("/oidc/token", params) |> json_response(400)

    assert build_conn() |> get("/oidc/userinfo") |> response(401)
  end

  test "email is not disclosed without the email scope", %{client: client, user: user} do
    code = authorize(client, user, "openid profile", "nonce-2")
    result = build_conn() |> post("/oidc/token", token_params(client, code)) |> json_response(200)
    %{"keys" => [public]} = build_conn() |> get("/oidc/jwks") |> json_response(200)

    assert {true, jwt, _} =
             JOSE.JWT.verify_strict(JOSE.JWK.from_map(public), ["RS256"], result["id_token"])

    refute Map.has_key?(jwt.fields, "email")
    refute Map.has_key?(jwt.fields, "email_verified")
    assert jwt.fields["updated_at"] == DateTime.to_unix(user.updated_at)

    info =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> result["access_token"])
      |> get("/oidc/userinfo")
      |> json_response(200)

    assert info == %{
             "sub" => user.id,
             "updated_at" => DateTime.to_unix(user.updated_at)
           }
  end

  test "profile claims are not disclosed without the profile scope", %{
    client: client,
    user: user
  } do
    code = authorize(client, user, "openid email", "nonce-3")
    result = build_conn() |> post("/oidc/token", token_params(client, code)) |> json_response(200)
    %{"keys" => [public]} = build_conn() |> get("/oidc/jwks") |> json_response(200)

    assert {true, jwt, _} =
             JOSE.JWT.verify_strict(JOSE.JWK.from_map(public), ["RS256"], result["id_token"])

    refute Map.has_key?(jwt.fields, "updated_at")

    info =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> result["access_token"])
      |> get("/oidc/userinfo")
      |> json_response(200)

    assert info == %{
             "sub" => user.id,
             "email" => "oidc-test@example.com",
             "email_verified" => false
           }
  end

  test "missing nonce and redirect URI mismatch are rejected", %{client: client, user: user} do
    params = authorization_params(client, "openid email", "nonce")

    assert build_conn()
           |> get("/oidc/authorize", Map.delete(params, "nonce"))
           |> json_response(400)

    assert build_conn()
           |> get(
             "/oidc/authorize",
             Map.put(params, "redirect_uri", "http://localhost:4999/auth/user/authx/callback")
           )
           |> json_response(400)

    code = authorize(client, user, "openid email", "nonce")
    wrong_uri = Map.put(token_params(client, code), "redirect_uri", "http://localhost:4001/wrong")

    assert %{"error" => "invalid_grant"} =
             build_conn() |> post("/oidc/token", wrong_uri) |> json_response(400)
  end

  defp authorize(client, user, scope, nonce) do
    conn =
      build_conn()
      |> init_test_session(%{})
      |> AshAuthentication.Plug.Helpers.store_in_session(user)
      |> get("/oidc/authorize", authorization_params(client, scope, nonce))

    html = conn |> html_response(200) |> LazyHTML.from_document()
    assert [signed] = LazyHTML.attribute(html["input[name='consent_request']"], "value")

    callback =
      conn
      |> recycle()
      |> post("/oidc/authorize", %{"consent_request" => signed, "action" => "approve"})
      |> redirected_to()

    assert %{"code" => code, "state" => "state"} =
             callback |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    code
  end

  defp authorization_params(client, scope, nonce) do
    %{
      "client_id" => client.id,
      "redirect_uri" => @redirect_uri,
      "response_type" => "code",
      "scope" => scope,
      "state" => "state",
      "nonce" => nonce,
      "code_challenge" => Base.url_encode64(:crypto.hash(:sha256, @verifier), padding: false),
      "code_challenge_method" => "S256"
    }
  end

  defp token_params(client, code) do
    %{
      "grant_type" => "authorization_code",
      "client_id" => client.id,
      "code" => code,
      "redirect_uri" => @redirect_uri,
      "code_verifier" => @verifier
    }
  end
end
