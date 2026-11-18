# OIDC ID Token 签名密钥（`Authx.Oauth.Oidc.Keys`）

本文说明 Authx 如何持有 OIDC 签名私钥、签发 ID Token，以及把公钥发布给
客户端的完整链路。适用于排查签名失败、JWKS 缓存、重启后 token 失效等问题。

相关代码：

- [`lib/authx/oauth/oidc/keys.ex`](../lib/authx/oauth/oidc/keys.ex)
- [`lib/authx_web/controllers/oidc_controller.ex`](../lib/authx_web/controllers/oidc_controller.ex)
- [`lib/authx/secrets.ex`](../lib/authx/secrets.ex)
- [`config/runtime.exs`](../config/runtime.exs)

## 定位

`Authx.Oauth.Oidc.Keys` 是 **ID Token 的 RS256 签名密钥管理器**：

- 在进程内持有 RSA 私钥；
- 对外提供 `sign/1` 签发 ID Token；
- 对外提供 `public_key/0` 返回公钥 JWK，供 `/oidc/jwks` 发布。

它只负责 ID Token。OIDC 的 access token 由
`ash_authentication_oauth2_server` 用对称密钥（`oauth2_signing_secret`）
签发和校验，不经过 JWKS，也不由本模块管理。

## 为什么是 RS256

当前实现固定 RS256，主要原因是互操作性，而不是 RSA 在密码学上更先进：

- OIDC Core 要求 OP 支持 RS256，它是规范基线；
- 客户端生态（尤其浏览器插件和其他语言 SDK）对 RS256 的支持最广；
- RS256 + RSA-2048 在当前威胁模型下仍然安全，验签开销对身份提供方不是
  瓶颈。

更现代的 ES256（P-256）或 EdDSA（Ed25519）有更小的密钥和签名、更快的
验签，但客户端支持度不均衡。若要引入：

- 继续保留 RS256 作为基线，不拿掉；
- 在 `Keys`、JWKS、discovery 和客户端验证中同时支持新算法；
- 优先考虑 ES256；EdDSA 需要先确认所有接入方都支持。

算法升级不会改变当前更重要的限制：单密钥、无轮换、没有 `kid` 历史。

## 启动与密钥来源

`Authx.Oauth.Oidc.Keys` 是命名 GenServer，随应用启动：

```elixir
# lib/authx/application.ex
Authx.Oauth.Oidc.Keys
```

启动时 `init/1` 按配置决定私钥：

| 环境 | `:oidc_private_key_file` | 行为 |
|---|---|---|
| prod | `AUTHX_OIDC_PRIVATE_KEY_FILE` 必填 | 读取 PEM 文件；校验必须是 RSA 私钥（`kty == "RSA"` 且含私钥参数 `d`） |
| dev / test | 通常未配置 | 启动时用 `JOSE.JWK.generate_key({:rsa, 2048})` 临时生成 |

随后计算：

- `kid = JOSE.JWK.thumbprint(key)`：RFC 7638 公钥指纹，同一把 key 恒定；
- 公钥 JWK：`JOSE.JWK.to_public/1` 转为 map，再补上
  `kid`、`use: "sig"`、`alg: "RS256"`。

GenServer 状态：

```elixir
%{key: 私钥, kid: kid, public: 公钥JWK}
```

## 生成 prod 私钥文件

使用项目自带的 mix task 生成：

```sh
mix gen.oidc.private_key /secure/path/authx_oidc_private_key.pem
```

行为：

- 生成 RSA-2048 私钥 PEM；
- 文件权限设置为 `0600`；
- 目标文件已存在时拒绝覆盖；
- 输出 `kid`，可用于和 `/oidc/jwks` 返回的公钥对照。

把文件挂载到 release 运行环境，并设置：

```sh
AUTHX_OIDC_PRIVATE_KEY_FILE=/run/secrets/authx_oidc_private_key.pem
```

密钥不要提交到仓库，也不要在每次部署时重新生成——更换密钥会让已签发的
ID Token 立即失效。

## 签发 ID Token

`POST /oidc/token` 在
[`OidcController.token/2`](../lib/authx_web/controllers/oidc_controller.ex)
中完成授权码兑换后构造 claims：

```elixir
%{
  "iss" => issuer,
  "sub" => user.id,
  "aud" => code.client_id,
  "iat" => now,
  "exp" => now + 300,
  "nonce" => code.nonce
}
```

再按 scope 追加 `email` / `email_verified` / `updated_at`，最后调用：

```elixir
Keys.sign(claims)
```

`sign/1` 固定使用 RS256，并把 `kid` 放入 JWT header：

```elixir
JOSE.JWT.sign(key, %{"alg" => "RS256", "kid" => kid}, claims)
|> JOSE.JWS.compact()
```

## 公钥发布与客户端验证

1. Discovery：`GET /.well-known/openid-configuration`
   - `jwks_uri` = `issuer <> "/oidc/jwks"`
   - `id_token_signing_alg_values_supported` = `["RS256"]`
2. JWKS：`GET /oidc/jwks` 返回

   ```json
   { "keys": [{ "kty": "RSA", "kid": "...", "use": "sig", "alg": "RS256", ... }] }
   ```

3. 客户端用 ID Token header 里的 `kid` 选中公钥，验证 RS256 签名，再校验
   `iss`、`aud`、`exp` 和 `nonce`。

私钥始终留在 Authx 进程内，客户端只需要公钥，这正是不对称签名的意义。

## 为什么用 GenServer

- 密钥只在启动时加载一次，避免每次签名都读文件或生成 key；
- 私钥集中在单进程中，签名调用天然串行；
- 进程崩溃会由 supervisor 重启；prod 指定密钥文件时重启后 key 不变。

## dev/test 与 prod 的差异

| 项目 | dev / test | prod |
|---|---|---|
| 私钥 | 每次启动临时生成 | 从 `AUTHX_OIDC_PRIVATE_KEY_FILE` 加载 |
| `kid` | 每次重启变化 | 稳定 |
| 重启后的旧 ID Token | 无法再验证 | 仍可验证 |
| 客户端 JWKS 缓存 | 重启后可能过期 | 保持有效 |

因此 prod 必须提供固定私钥文件；dev/test 的临时 key 只用于本地调试。

## 当前限制

- **单密钥、无轮换**：JWKS 只返回一把 key，没有 kid 历史列表；替换私钥会
  立即使旧 ID Token 失去验证能力。
- **无密钥版本管理**：没有 `kid` 的多版本并存机制，轮换需要同时修改
  `/oidc/jwks` 的返回结构。
- **算法固定 RS256**：不存在 `none` 或动态算法协商。
- **access token 不在 JWKS 中**：它用对称密钥签发，由 Authx 自己校验。

## 排查要点

- **客户端签名验证失败**：先确认 ID Token header 的 `kid` 是否出现在
  `/oidc/jwks` 返回的列表中；dev 重启后 `kid` 会变化。
- **prod 启动失败**：检查 `AUTHX_OIDC_PRIVATE_KEY_FILE` 是否存在、是否为
  RSA 私钥 PEM。
- **JWKS 缓存**：客户端通常缓存 JWKS；dev 频繁重启时需要清缓存或重新拉取。
- **`exp` 很短**：ID Token 当前有效期为 300 秒，验证时注意时钟偏差。
