# OIDC 客户端认证与公开客户端威胁模型

本文说明 Authx 作为 OIDC 授权服务器时，`token_endpoint_auth_method` 的语义、
当前只支持公开客户端（`none`）时的安全边界，以及后续支持
`client_secret_basic`、`client_secret_post`、`private_key_jwt`、mTLS 等
机密客户端认证方式的建议路线。

协议端点与整体架构见 [OAuth 2.1 与 OIDC 架构说明](oauth-and-oidc-architecture.md)，
生产门禁见 [OIDC 生产化与上线计划](oidc-production.md)。

---

## 1. 结论

- `client_id` **不是凭据**。它是客户端的公开标识，出现在浏览器地址栏、
  授权请求和日志中都是正常的。
- 公开客户端（`token_endpoint_auth_method=none`）下，任何知道 `client_id`
  的程序都可以**发起授权请求**，但无法冒充该客户端**拿到令牌**。
- 防止冒充的不是 `client_id` 的保密性，而是：
  1. 回调地址精确匹配；
  2. S256 PKCE；
  3. `state` / `nonce`；
  4. 用户登录与 consent；
  5. 授权码一次性、短期有效。
- 当前 Authx **没有实现机密客户端认证**。上游
  `ash_authentication_oauth2_server` 0.4 明确只支持公开客户端，token 端点
  会拒绝任何客户端凭据。
- 增加其他认证方式不是只改一个字段：需要同时修改上游 token 校验、discovery
  元数据、客户端注册校验、密钥存储与轮换、错误语义和测试。建议按本文第 6
  节分阶段推进。

---

## 2. 术语

| 术语 | 含义 |
|---|---|
| 公开客户端 | 无法安全保存 secret 的客户端，例如浏览器 SPA、原生应用、桌面应用。注册为 `token_endpoint_auth_method=none`。 |
| 机密客户端 | 能安全保存 secret 或私钥的服务端应用。可使用 `client_secret_basic`、`client_secret_post`、`private_key_jwt`、mTLS 等方式在 token 端点证明身份。 |
| 客户端认证 | 客户端向授权服务器证明“我是哪个客户端注册记录”，**不是**用户身份认证。 |
| PKCE | 把授权码绑定到发起授权的客户端实例，防止授权码被其他客户端截获后兑换。它**不能替代**客户端认证。 |
| `client_id` | 客户端注册记录的公开标识，不是秘密。 |
| `client_secret` | 机密客户端的共享密钥，属于凭据，必须保密。 |

---

## 3. 当前实现事实

以下为当前代码的实际行为，是后续增强的基线：

| 项目 | 现状 | 位置 |
|---|---|---|
| discovery 公布的方法 | 仅 `["none"]` | `lib/authx_web/controllers/oidc_controller.ex` |
| 客户端注册校验 | 只允许 `token_endpoint_auth_method="none"` | `lib/authx/oauth/client.ex` |
| token 端点客户端校验 | 任何 `client_secret`、`client_assertion` 或 `Authorization: Basic` 都会被拒绝 | `ash_authentication_oauth2_server` 的 `Token.check_no_client_credentials/2` |
| 客户端凭据错误 | 返回 `400 invalid_client`（描述为 `public client`） | 上游 `AshAuthentication.Phoenix.Oauth2Server.Errors` |
| PKCE | 授权码流程强制 S256 | `AuthorizationCode` + 上游 `PKCE` |
| 重定向地址 | 必须与注册的 `redirect_uris` 精确匹配 | `validate_request/1` |
| 动态注册 / CIMD | 均关闭 | `Authx.Oauth.Oidc.Server` |
| 速率限制 / 审计 | 尚未实现 | 见生产化计划 |
| 刷新令牌 | 上游支持，但 Authx 当前 discovery 只公布 `authorization_code` | `lib/authx_web/controllers/oidc_controller.ex` |

上游 0.4 的核心假设写在 `Token` 模块注释中：

> Every client here is public (`token_endpoint_auth_method: "none"`), so there
> is nothing to check the credentials against.

因此，**只在 Authx 的 `Client` 资源里放开一个校验值并不能启用机密客户端**：
token 交换仍会因携带凭据而被上游拒绝。

---

## 4. 公开客户端（`none`）威胁模型

### 4.1 攻击者能做什么

假设攻击者知道 foo 的 `client_id`，并知道 Authx 的公开端点：

| 行为 | 是否能做到 | 结果 |
|---|---|---|
| 构造 `/oidc/authorize` 请求 | 能 | 浏览器被带到 Authx；用户可能看到 foo 的名称和 consent 页 |
| 修改 `redirect_uri` 为自己的地址 | 不能 | Authx 要求与注册值精确匹配，返回 `invalid_request` |
| 收到授权码 | 不能 | 授权码只会重定向到注册回调（foo） |
| 用授权码换 token | 不能 | 需要 foo 持有的 PKCE `code_verifier`；授权码一次性 |
| 伪造用户登录 | 不能 | 必须经过 Authx 登录与 consent |
| 用 `client_id` 访问 UserInfo | 不能 | 需要有效 access token |
| 反复触发授权/consent/token 请求 | 能 | 当前没有速率限制，可能造成骚扰或资源消耗 |
| 诱导用户授权一个恶意应用 | 部分能 | 若攻击者自己注册/拥有客户端并让用户 consent，这是正常授权模型；不是冒用 foo |

### 4.2 现有防护链路

1. **注册时**：回调必须是 HTTPS 或 loopback HTTP，且属于 developer。
2. **授权时**：校验 `client_id`、精确回调、scope 子集、response type、
   grant type、PKCE challenge、nonce、用户登录与 consent。
3. **发码时**：授权码绑定客户端、用户、回调、scope、PKCE challenge、nonce、
   过期时间，且一次性消费。
4. **兑换时**：校验授权码未使用/未过期、客户端匹配、回调匹配、PKCE
   verifier、resource 匹配。
5. **ID Token**：RS256 签名，校验 issuer、audience、时效、nonce。

### 4.3 残余风险

- **骚扰与资源消耗**：任意人可反复触发授权页或无效 token 请求。需要速率限制、
  审计和告警。
- **Consent 钓鱼**：攻击者可把用户引到一个真实但与其意图不符的客户端
  consent 页；consent 页必须清楚显示客户端名称、回调来源与 scope。
- **授权码 / verifier 泄露**：若 foo 的日志、错误上报或浏览器扩展泄露
  `code_verifier`、授权码或 token，攻击者可兑换或重放。客户端侧必须避免记录
  这些值。
- **设备或浏览器已被攻陷**：PKCE/nonce 无法防御同一浏览器会话内的恶意扩展
  或恶意软件。
- **客户端标识滥用无法在协议层区分**：对公开客户端而言，授权服务器无法判断
  发起授权请求的是“真正的 foo”还是“知道 client_id 的其他程序”。这是公开
  客户端的固有属性，只能通过回调绑定、PKCE、consent 和速率限制缓解。
- **错误语义**：当前客户端凭据错误返回 400；OAuth 2.1 / RFC 6749 对使用
  `Authorization` 头的客户端认证失败建议返回 401 并带 `WWW-Authenticate`
  挑战。引入 Basic 认证时应一并修正。

---

## 5. 为什么增强客户端认证需要跨层修改

支持其他 `token_endpoint_auth_method` 至少涉及五层：

1. **discovery**：`token_endpoint_auth_methods_supported` 不能再只写 `none`。
2. **注册 / 管理**：`Client` 资源、注册 action、开发者控制台和
   `mix dev.seed` 需要接受并校验新的方法值。
3. **凭据存储**：新增 secret 哈希、签发时间、过期/轮换信息，或客户端公钥 /
   JWKS / 证书指纹；需要迁移与安全存储。
4. **token 端点**：解析 `Authorization: Basic`、表单 `client_id` +
   `client_secret` 或 `client_assertion`；按客户端注册的方法校验；拒绝多机制
   混用；统一 `invalid_client` 行为。
5. **测试与运维**：正负向测试、时钟偏差、重放、轮换、撤销、审计和速率限制。

上游库把这套逻辑封闭在 `Token` 模块与 `ClientMetadata` 校验中，因此需要
**上游支持**或**本地实现替代层**，不能只靠 Authx 资源校验。

---

## 6. 增强路线建议

### 6.1 前置能力（先于任何新认证方式）

无论选择哪种方式，以下能力应先具备：

- **速率限制**：授权、consent、token 端点按 IP / 客户端 / 用户维度限流。
- **审计日志**：记录客户端认证失败、token 兑换、consent、刷新令牌轮换与
  撤销；日志中不得包含 secret、断言、授权码、verifier、token 明文。
- **客户端生命周期**：secret/密钥的创建、显示一次、轮换、撤销、过期。
- **错误语义统一**：`invalid_client`、`invalid_request`、`unauthorized_client`
  与 HTTP 状态码、`WWW-Authenticate` 头符合 RFC 6749 / OAuth 2.1。
- **TLS 强制**：包含 secret、断言或授权码的端点必须仅通过 HTTPS 暴露。

### 6.2 阶段一：`client_secret_basic` 与 `client_secret_post`

适用：传统服务端 Web 应用、能安全保存 secret 的 BFF。

**协议要点**

- 推荐 `client_secret_basic`：`Authorization: Basic base64(client_id:client_secret)`。
  注意先对 `client_id`/`client_secret` 做 form-urlencode 再拼接（RFC 6749
  §2.3.1）。
- `client_secret_post` 作为兼容选项：secret 出现在请求体，必须仅走 TLS，
  并避免被请求体日志记录。
- 一次请求只能使用一种客户端认证机制；混用返回 `invalid_request`。
- 认证失败：
  - 使用 Basic 时返回 `401` + `WWW-Authenticate: Basic realm="..."`；
  - 其他方式返回 `401 invalid_client`（视实现与兼容性要求）。
- 公开客户端继续使用 `none` + PKCE；机密客户端也应继续使用 PKCE（OAuth 2.1
  要求 authorization code 流程使用 PKCE）。

**存储建议**

- 客户端 secret 使用高熵随机值（至少 256 bit），只在创建/轮换时显示一次。
- 存储哈希而非明文。高熵 secret 可用 HMAC-SHA256（服务端 pepper）或
  SHA-256；若允许低熵或用户自定义 secret，使用 Argon2/bcrypt。比较时使用
  恒定时间比较。
- 记录 `client_secret_issued_at`、`client_secret_expires_at`、
  `client_secret_rotated_at`，支持双 secret 过渡期。
- 撤销后立即失效；轮换需要审计。

**数据模型草案**

```elixir
# Authx.Oauth.Resources.Client 新增
attribute :client_secret_hash, :string, sensitive?: true
attribute :client_secret_issued_at, :utc_datetime_usec
attribute :client_secret_expires_at, :utc_datetime_usec
attribute :previous_client_secret_hash, :string, sensitive?: true

# token_endpoint_auth_method 从 "none" 扩展为枚举
# "none" | "client_secret_basic" | "client_secret_post"
```

### 6.3 阶段二：`private_key_jwt`

适用：能管理私钥、希望避免共享 secret 的服务端客户端。

**协议要点**

- 客户端用私钥签名 JWT，通过 `client_assertion_type` +
  `client_assertion` 提交（RFC 7523，OIDC Core §9）。
- 校验：
  - `iss` 与 `sub` 都等于 `client_id`；
  - `aud` 等于 token 端点或 issuer；
  - `exp` 很短（例如 ≤ 5 分钟），`iat` 在允许的时钟偏差内；
  - `jti` 防重放（短期缓存或持久化已用 jti）；
  - 签名算法在白名单内，禁止 `none` 与对称算法；
  - 公钥来自注册的 `jwks` 或 `jwks_uri`，支持 `kid` 轮换。
- 客户端可注册 `token_endpoint_auth_signing_alg`，服务器只接受该算法。

**存储建议**

- 保存客户端 JWKS 或 `jwks_uri`，不要保存私钥。
- 若使用 `jwks_uri`，需要 SSRF 防护、缓存、超时和失败回退策略。
- 支持多个公钥并保留旧 key 一段时间，便于轮换。

### 6.4 阶段三：mTLS（`tls_client_auth` / `self_signed_tls_client_auth`）

适用：高信任服务端环境，已有证书签发和轮换能力。

- 需要反向代理或 Plug 层提供客户端证书信息（例如 `Plug.SSL` 的 peer
  certificate 或代理注入的可信头）。
- 校验证书链、subject/SAN 与注册信息一致，或证书指纹等于注册值。
- 签发含 `cnf.x5t#S256` 的 sender-constrained access token（RFC 8705）。
- 运维成本最高：证书签发、吊销、轮换、代理信任边界都必须明确。

### 6.5 与 DPoP 的关系

DPoP（RFC 9449）不是客户端认证方式，而是把 access token 绑定到客户端持有的
密钥，防止 bearer token 被盗用。它可与公开客户端或机密客户端组合，属于后续
独立增强项。

浏览器插件是一种特殊但常见的公开客户端场景：插件登录 Authx 可以直接使用
`none` + PKCE，但插件直接调用业务 API 需要额外的 resource/audience 设计。
详见 [浏览器插件接入 Authx OIDC](browser-extension-oidc.md)。

### 6.6 不建议的做法

- **把 `client_secret` 放进浏览器或移动端**：无法保密，等同于公开客户端。
- **用 PKCE 替代客户端认证**：PKCE 绑定授权码，不证明客户端身份。
- **在 query string 传 secret**：会进入日志、浏览器历史和代理。
- **为兼容性接受多种认证机制同时出现**：应明确拒绝并记录。
- **明文存储 secret 或断言**：任何日志、备份和错误上报都可能泄露。
- **只改 discovery 元数据而不改 token 校验**：会造成客户端误以为支持而实际失败。

---

## 7. 落地方式：上游优先

推荐顺序：

1. **优先向上游 `ash_authentication_oauth2_server` 提交支持**
   - 增加按客户端 `token_endpoint_auth_method` 分派的认证模块；
   - 扩展 `ClientMetadata` 的合法方法与注册字段；
   - 提供 secret/JWKS 字段与校验钩子；
   - 扩展 discovery 元数据生成。
   这样 Authx、demo、foo 以及未来应用共享同一实现，避免分叉协议核心。

2. **Authx 层只做策略与数据**
   - `Client` 资源允许的方法、secret 生命周期、开发者控制台/任务；
   - 审计、速率限制、管理员操作；
   - 不复制上游的 PKCE/授权码/刷新令牌逻辑。

3. **短期过渡（不推荐长期）**
   - 若上游排期不可控，可在 Authx 内实现一个 token 端点前置层，完成客户端
     认证后把“已验证客户端”传给受信任的内部交换函数；
   - 但上游当前会拒绝任何凭据，因此仍需要 patch/fork，成本高于直接上游贡献；
   - 若 fork，必须固定版本、记录差异并建立升级测试，避免协议安全修复丢失。

---

## 8. 测试矩阵（增强后）

| 场景 | 预期 |
|---|---|
| `none` + 无凭据 + 正确 PKCE | 成功 |
| `none` + 携带 Basic / secret / assertion | `invalid_client`（或 `invalid_request`，按规范） |
| `client_secret_basic` + 正确 secret | 成功 |
| `client_secret_basic` + 错误 secret | 401 `invalid_client` + challenge |
| `client_secret_basic` + 错误 client_id | 401 `invalid_client` |
| `client_secret_post` + 正确 secret（HTTPS） | 成功 |
| 同一请求同时带 Basic 与 body secret | `invalid_request` |
| secret 过期 / 已轮换的旧 secret | `invalid_client` |
| `private_key_jwt` + 合法签名 | 成功 |
| `private_key_jwt` + 错误 aud / exp / jti 重放 / 未知 kid | `invalid_client` |
| `private_key_jwt` + 对称算法 | `invalid_client` |
| mTLS + 证书匹配 | 成功 |
| mTLS + 证书不匹配 / 未提供证书 | `invalid_client` |
| 公开客户端 + 任意客户端凭据 | 拒绝，且不消耗授权码 |
| 失败请求后的授权码 | 仍可在有效期内重试（除非已消费） |

同时补充：速率限制、审计字段、日志脱敏、secret 轮换与撤销的运维测试。

---

## 9. 优先级与决策建议

| 优先级 | 事项 | 理由 |
|---|---|---|
| P0 | 速率限制、审计、日志脱敏、错误语义修正 | 对当前公开客户端也有直接安全收益 |
| P1 | 上游支持 `client_secret_basic`（首选）/ `client_secret_post` | 覆盖大多数服务端应用，实现与运维成本最低 |
| P2 | `private_key_jwt` | 避免共享 secret，适合高信任服务端，但需要 JWKS 与重放防护 |
| P3 | mTLS / DPoP | 运维或生态成本高，按实际接入需求再启用 |

对 Authx 当前“超级个人开发者统一身份服务”的定位，建议先用 P0 + P1 满足
服务端应用接入；公开客户端（demo、foo、浏览器扩展）继续使用 `none` + PKCE，
不强行要求 secret。只有在出现明确的服务端高信任接入需求时，再投入 P2/P3。

---

## 10. 参考

- RFC 6749 §2.3.1：客户端认证（Basic / POST）
- RFC 7523：JWT 客户端断言
- RFC 7638：JWK Thumbprint
- RFC 8705：mTLS 客户端认证与证书绑定令牌
- RFC 9449：DPoP
- RFC 9700（OAuth 2.0 Security BCP）：公开客户端、PKCE、重定向校验
- OpenID Connect Core 1.0 §9：客户端认证与 `private_key_jwt`
- `ash_authentication_oauth2_server` 0.4 `Token` / `ClientMetadata` 模块注释
