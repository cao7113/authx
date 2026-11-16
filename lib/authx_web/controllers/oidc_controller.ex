defmodule AuthxWeb.OidcController do
  use AuthxWeb, :controller

  alias AshAuthentication.Oauth2Server.{Authorize, Token}
  alias AshAuthentication.Phoenix.Oauth2Server.{ConsentView, Errors}
  alias Authx.Accounts.User
  alias Authx.Oauth.AuthorizationCode
  alias Authx.Oauth.Oidc.{Keys, Server}

  @auth_context %{private: %{ash_authentication?: true}}
  @salt "authx oidc consent v1"
  @request_fields ~w(client_id redirect_uri response_type scope state code_challenge code_challenge_method resource nonce)

  def discovery(conn, _) do
    issuer = Server.issuer_url()

    metadata = %{
      issuer: issuer,
      authorization_endpoint: issuer <> "/oidc/authorize",
      token_endpoint: issuer <> "/oidc/token",
      userinfo_endpoint: issuer <> "/oidc/userinfo",
      jwks_uri: issuer <> "/oidc/jwks",
      response_types_supported: ["code"],
      subject_types_supported: ["public"],
      id_token_signing_alg_values_supported: ["RS256"],
      scopes_supported: ["openid", "email"],
      claims_supported: ["sub", "email", "email_verified"],
      grant_types_supported: ["authorization_code"],
      token_endpoint_auth_methods_supported: ["none"],
      code_challenge_methods_supported: ["S256"]
    }

    # 不发布 registration_endpoint：客户端由开发者控制台创建并归属某个
    # developer，动态注册无法证明开发者身份。
    json(conn, metadata)
  end

  def jwks(conn, _), do: json(conn, %{keys: [Keys.public_key()]})

  def authorize(conn, params) do
    with {:ok, validated} <- validate_request(params) do
      case Ash.PlugHelpers.get_actor(conn) do
        nil ->
          return_to = conn.request_path <> "?" <> conn.query_string

          conn
          |> put_session(:return_to, return_to)
          |> redirect(to: "/sign-in")

        user ->
          if Authorize.consented?(Server, user, validated.client, validated.scope) do
            issue_code(conn, user, validated, params["nonce"])
          else
            render_consent(conn, validated, params)
          end
      end
    else
      {:error, _, _, _} ->
        Errors.send_oauth_error(conn, 400, "invalid_request", "invalid client")

      {:error, _, _} ->
        Errors.send_oauth_error(conn, 400, "invalid_request", "invalid authorization request")

      {:error, _} ->
        Errors.send_oauth_error(conn, 400, "invalid_request", "invalid authorization request")
    end
  end

  def consent(conn, %{"consent_request" => signed, "action" => action})
      when is_binary(signed) and action in ["approve", "deny"] do
    with {:ok, params} <-
           Plug.Crypto.verify(Server.signing_secret(), @salt, signed, max_age: 600),
         {:ok, validated} <- validate_request(params),
         user when not is_nil(user) <- Ash.PlugHelpers.get_actor(conn) do
      if action == "approve" do
        Authorize.grant_consent!(Server, user, validated.client, validated.scope)
        conn |> configure_session(renew: true) |> issue_code(user, validated, params["nonce"])
      else
        authorization_redirect(conn, validated, %{"error" => "access_denied"})
      end
    else
      _ -> Errors.send_oauth_error(conn, 400, "invalid_request", "invalid consent request")
    end
  end

  def consent(conn, _),
    do: Errors.send_oauth_error(conn, 400, "invalid_request", "invalid consent request")

  def token(
        conn,
        %{"grant_type" => "authorization_code", "code" => id, "redirect_uri" => uri} = params
      )
      when is_binary(id) and is_binary(uri) and uri != "" do
    opts = [context: @auth_context]

    with {:ok, %AuthorizationCode{} = code} <- Ash.get(AuthorizationCode, id, opts),
         true <- is_binary(code.nonce) and code.nonce != "",
         true <- "openid" in String.split(code.scope, " ", trim: true),
         {:ok, %User{} = user} <- Ash.get(User, code.user_id, opts),
         {:ok, response} <-
           Token.exchange_authorization_code(Server, params, token_opts(conn)) do
      now = System.system_time(:second)

      claims =
        %{
          "iss" => Server.issuer_url(),
          "sub" => user.id,
          "aud" => code.client_id,
          "iat" => now,
          "exp" => now + 300,
          "nonce" => code.nonce
        }
        |> add_email(user, code.scope)

      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
      |> json(%{
        access_token: response.access_token,
        token_type: response.token_type,
        expires_in: response.expires_in,
        scope: response.scope,
        id_token: Keys.sign(claims)
      })
    else
      {:error, reason} when is_atom(reason) ->
        {status, code, description} = Errors.describe_token_error(reason)
        Errors.send_oauth_error(conn, status, code, description)

      _ ->
        Errors.send_oauth_error(conn, 400, "invalid_grant", "invalid authorization code")
    end
  end

  def token(conn, _),
    do: Errors.send_oauth_error(conn, 400, "invalid_request", "invalid token request")

  def userinfo(conn, _) do
    user = Ash.PlugHelpers.get_actor(conn)
    claims = %{"sub" => user.id} |> add_email(user, conn.assigns.oauth_claims["scope"])
    conn |> put_resp_header("cache-control", "no-store") |> json(claims)
  end

  defp validate_request(params) when is_map(params) do
    with nonce when is_binary(nonce) and byte_size(nonce) in 1..256 <- params["nonce"],
         true <-
           Enum.all?(
             ~w(prompt max_age claims request request_uri),
             &(not Map.has_key?(params, &1))
           ),
         {:ok, validated} <- Authorize.validate_request(Server, params),
         true <- validated.redirect_uri in validated.client.redirect_uris,
         requested <- MapSet.new(String.split(validated.scope, " ", trim: true)),
         allowed <- MapSet.new(String.split(validated.client.scope || "", " ", trim: true)),
         true <- MapSet.member?(requested, "openid") and MapSet.subset?(requested, allowed),
         true <- "authorization_code" in (validated.client.grant_types || ["authorization_code"]),
         true <- "code" in (validated.client.response_types || ["code"]) do
      {:ok, validated}
    else
      {:error, _, _, _} = error -> error
      {:error, _, _} = error -> error
      _ -> {:error, :invalid_request}
    end
  end

  defp validate_request(_), do: {:error, :invalid_request}

  defp render_consent(conn, validated, params) do
    signed =
      Plug.Crypto.sign(Server.signing_secret(), @salt, Map.take(params, @request_fields))

    body =
      ConsentView.render(:consent, %{
        client_name: validated.client.client_name,
        client_id: validated.client.id,
        redirect_uri: validated.redirect_uri,
        code_challenge: validated.code_challenge,
        scope: validated.scope,
        state: validated.state,
        resource: validated.resource,
        action_path: conn.request_path,
        csrf_token: Plug.CSRFProtection.get_csrf_token(),
        consent_request: signed
      })

    conn
    |> put_resp_header("content-security-policy", "frame-ancestors 'none'")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_content_type("text/html")
    |> send_resp(200, body)
  end

  defp issue_code(conn, user, validated, nonce) do
    code =
      AuthorizationCode
      |> Ash.Changeset.for_create(:create, %{
        client_id: validated.client.id,
        user_id: user.id,
        redirect_uri: validated.redirect_uri,
        code_challenge: validated.code_challenge,
        scope: validated.scope,
        resource_uri: validated.resource,
        nonce: nonce,
        expires_at: DateTime.add(DateTime.utc_now(), Server.authorization_code_lifetime())
      })
      |> Ash.create!(context: @auth_context)

    authorization_redirect(conn, validated, %{"code" => code.id})
  end

  defp authorization_redirect(conn, validated, params) do
    params =
      params
      |> Map.put("iss", Server.issuer_url())
      |> then(fn params ->
        if validated.state, do: Map.put(params, "state", validated.state), else: params
      end)

    separator = if URI.parse(validated.redirect_uri).query, do: "&", else: "?"
    redirect(conn, external: validated.redirect_uri <> separator <> URI.encode_query(params))
  end

  defp add_email(claims, user, scope) do
    if "email" in String.split(scope, " ", trim: true) do
      Map.merge(claims, %{
        "email" => to_string(user.email),
        "email_verified" => not is_nil(user.confirmed_at)
      })
    else
      claims
    end
  end

  defp token_opts(conn) do
    case get_req_header(conn, "authorization") do
      [] -> []
      _ -> [authorization_scheme: "basic"]
    end
  end
end
