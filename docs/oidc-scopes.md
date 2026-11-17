# OIDC Scope 实现说明

本文说明 Authx 作为 OpenID Connect 身份提供商（IdP）时 scope 的语义、校验路径，
以及 `openid`、`email`、`profile` 三个 scope 的具体实现。协议端点与整体架构见
[OAuth 2.1 与 OIDC 架构说明](oauth-and-oidc-architecture.md)。

---

## 1. scope 是什么

在 OAuth 2.1 中，scope 是客户端为一次授权请求**声明访问意图**的字符串；
在 OIDC Core §5.4 中，scope 进一步被定义为**一组标准 claim 的集合名**。
它既不是角色（role），也不是细粒度权限（permission），更不是鉴权结果本身。

Authx 中一次授权请求的 scope 必须同时满足三层约束：

| 层 | 位置 | 作用 |
|---|---|---|
| 服务端目录 | `Authx.Oauth.Oidc.Server` 的 `scopes:` 选项 | 服务端支持哪些 scope；`enforce_scopes?: true`（默认）时请求的每个 token 必须在此列表内 |
| 客户端白名单 | `Authx.Oauth.Client` 的 `scope` 字段 | 某个客户端被允许请求哪些 scope |
| 用户同意 | `Authx.Oauth.Consent` 的 `scope` 字段 | 用户实际批准过哪些 scope |

任何一层缺失都会导致请求失败或重新弹出同意页。此外，OIDC 请求**必须包含
`openid`**，否则按普通 OAuth 2.0 处理，而 Authx 当前直接拒绝这种请求。

### 1.1 服务端目录

```elixir
# lib/authx/oauth/oidc/server.ex
use AshAuthentication.Oauth2Server,
  scopes: ["openid", "email", "profile"],
  ...
```

`AshAuthentication.Oauth2Server` 在 `enforce_scopes?: true` 时，用该列表校验
`/oidc/authorize` 的 `scope` 参数。scope 目录还参与 RFC 8707 的资源选择；
Authx 只注册了单 resource，因此 `aud` 固定为 `resource_url`。

### 1.2 客户端白名单

`Authx.Oauth.Client.scope` 是空格分隔的字符串，由开发者在注册客户端时指定。
授权请求会额外校验 `requested ⊆ client.scope`：

```elixir
# lib/authx_web/controllers/oidc_controller.ex
requested <- MapSet.new(String.split(validated.scope, " ", trim: true)),
allowed <- MapSet.new(String.split(validated.client.scope || "", " ", trim: true)),
true <- MapSet.member?(requested, "openid") and MapSet.subset?(requested, allowed)
```

因此"服务端支持 `profile`"不等于"所有客户端都能拿到 `profile`"——每个客户端仍需
在注册信息中显式登记。

### 1.3 用户同意

`Authorize.grant_consent!/5` 把批准的 scope 按 `(user_id, client_id)` 持久化。
两条关键语义：

- `consented?/5` 只在**已存 scope 是本次请求 scope 的超集**时跳过同意页；
- `grant_consent!/5` 会把新 scope **合并**进旧记录。

例如用户先同意 `openid`，客户端之后改为请求 `openid email profile` 时会再次
弹出同意页，批准后记录变为 `"openid email profile"`。这避免了静默扩权。

---

## 2. 支持的 scope 与 claim 一览

| scope | 目的 | 在 ID Token 中下发 | 在 UserInfo 中下发 |
|---|---|---|---|
| `openid` | OIDC 认证请求的协议开关 | 必需；决定是否签发 ID Token | 访问 `/oidc/userinfo` 的前置条件 |
| `email` | 邮箱相关声明 | `email`、`email_verified` | 同左 |
| `profile` | 标准资料声明 | `updated_at`（当前唯一有数据支撑的声明） | 同左 |

---

## 3. `openid`：协议开关

`openid` 本身不产出任何 claim。按 OIDC Core §3.1.2.1，只有 scope 含 `openid`
时这次请求才是 OIDC 认证请求；否则只是普通 OAuth 2.0。Authx 将它落实到四个位置：

### 3.1 授权请求必须带 `openid`

[`OidcController.validate_request/1`](../lib/authx_web/controllers/oidc_controller.ex)
要求：

- `openid ∈ requested scope`；
- `nonce` 非空且长度 1–256 字节；
- 拒绝 `prompt`、`max_age`、`claims`、`request`、`request_uri` 等高级参数；
- `response_type=code`、`code_challenge_method=S256`。

### 3.2 token 端点决定是否签发 ID Token

`POST /oidc/token` 在换取 access token 前检查授权码上的 `scope` 含 `openid`，
且授权码绑定了 `nonce`；不满足则不签发 `id_token`。

### 3.3 ID Token 的构造与签名

ID Token 是 JWT，claims 包括：

| claim | 值 |
|---|---|
| `iss` | `Server.issuer_url()` |
| `sub` | 用户 ID（`public` subject） |
| `aud` | 客户端 `client_id` |
| `iat` / `exp` | 签发时间 / 5 分钟后过期 |
| `nonce` | 授权请求中的 nonce，用于防重放 |

签名算法为 **RS256**，带 `kid`；公钥通过 `GET /oidc/jwks` 发布。密钥由
`Authx.Oauth.Oidc.Keys`（GenServer）管理。

### 3.4 UserInfo 的门禁

`/oidc/userinfo` 依次经过两个 plug：

1. `AshAuthentication.Phoenix.Oauth2Server.BearerPlug`：验证 access token 的签名、
   `iss`、`aud`、`exp`、`nbf`，恢复 actor，并把 claims 放入
   `conn.assigns.oauth_claims`；
2. `RequireScopePlug scope: "openid"`：要求 access token 的 `scope` claim 含
   `openid`。

access token 由依赖库的 `Token` 模块签发为 JWT，claims 含
`sub`、`client_id`、`scope`、`jti` 等；它和 ID Token 使用不同的签名密钥与用途，
不能互换。

---

## 4. `email`：邮箱声明

按 OIDC Core §5.4，`email` scope 请求 `email` 与 `email_verified` 两个 claim。
实现集中在 `OidcController.add_email/3`：

```elixir
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
```

调用点有两处：

- **ID Token**：使用授权码上已批准的 `code.scope`；
- **UserInfo**：使用 `conn.assigns.oauth_claims["scope"]`，即**已验证 access token**
  里的 scope，而不是请求参数。客户端无法在 UserInfo 阶段自行扩大 scope。

`email_verified` 没有独立存储字段，由 `user.confirmed_at` 是否为 `nil` 推导。
因此邮箱验证流程必须写入 `confirmed_at`，否则所有用户都会对客户端显示
`email_verified: false`。

---

## 5. `profile`：标准资料声明

按 OIDC Core §5.4，`profile` scope 请求 `name`、`family_name`、`given_name`、
`preferred_username`、`picture`、`locale`、`updated_at` 等一组标准 claim。
**scope 只授予访问权，不要求 IdP 必须返回全部 claim**：IdP 没有的数据可以省略。

当前 `Authx.Accounts.User` 只持久化了 `id`、`email`、`confirmed_at`、`role`、
`inserted_at`、`updated_at`，因此实现只下发有真实数据支撑的 `updated_at`：

```elixir
defp add_profile(claims, user, scope) do
  if "profile" in String.split(scope, " ", trim: true) do
    Map.put(claims, "updated_at", DateTime.to_unix(user.updated_at))
  else
    claims
  end
end
```

- 与 `email` 一样，同时作用于 ID Token 和 UserInfo，且 UserInfo 读取 access token
  的 `scope`。
- `updated_at` 使用 Unix epoch 秒（1970-01-01 起）。OIDC Core §5.1 原文写作
  1976-01-01 起，这是规范中广为人知的笔误；实际实现普遍按 Unix 时间戳传输。
- 不返回 `preferred_username` 或 `name` 之类的推导值。把 email 填进
  `preferred_username` 会让 `profile` scope 泄露本应由 `email` scope 控制的数据，
  破坏 scope 隔离。

后续如果用户模型增加 `name`、`nickname`、`locale` 等字段，在 `add_profile/3` 中
按同样的"仅下发有数据支撑的 claim"原则扩展即可。

---

## 6. 一次请求的 scope 流转

以 `scope=openid email profile` 为例：

```text
GET /oidc/authorize
  ├─ Server.scopes() 校验 openid/email/profile 均被服务端支持
  ├─ client.scope 校验三者均被该客户端登记
  ├─ 要求 openid 且 nonce 存在
  └─ Authorize.consented?/5
       ├─ 已同意且旧 scope 覆盖三者 → 直接签发授权码
       └─ 否则渲染同意页；approve 后 grant_consent!/5 合并 scope 并签发授权码
              （授权码记录 scope、nonce、PKCE challenge、redirect_uri）

POST /oidc/token
  ├─ 校验授权码未过期/未使用、client 与 redirect_uri 匹配、PKCE verifier
  ├─ 要求 code.scope 含 openid，且 nonce 非空
  ├─ 签发 access token（含 scope claim）
  └─ 签发 ID Token：iss/sub/aud/iat/exp/nonce + add_email + add_profile

GET /oidc/userinfo
  ├─ BearerPlug 验证 access token 并写入 oauth_claims
  ├─ RequireScopePlug 要求 scope 含 openid
  └─ sub + add_email(access_token.scope) + add_profile(access_token.scope)
```

---

## 7. Discovery 元数据的一致性

`GET /.well-known/openid-configuration` 由
[`OidcController.discovery/2`](../lib/authx_web/controllers/oidc_controller.ex)
手写，**不会自动读取** `Server.scopes()`：

```elixir
scopes_supported: ["openid", "email", "profile"],
claims_supported: ["sub", "email", "email_verified", "updated_at"],
```

因此 scope 配置、discovery 与实际 claim 组装是三份独立数据。新增或移除 scope 时
必须同步修改，否则会出现"元数据宣称支持但实际不下发"或反之的不一致。

---

## 8. 新增一个 scope 的检查清单

1. **服务端目录**：在 `Authx.Oauth.Oidc.Server` 的 `scopes:` 中加入新 scope。
2. **Discovery**：同步 `scopes_supported`，需要时同步 `claims_supported`。
3. **Claim 组装**：在 `OidcController` 增加与 `add_email/3`、`add_profile/3` 同风格的
   函数，并在 ID Token 与 UserInfo 两条路径都调用。
4. **同意页**：确认 `ConsentView` 能展示新 scope；必要时补充说明文案。
5. **客户端白名单**：新 scope 只对显式登记了它的客户端生效。更新开发者控制台、
   种子数据或测试 fixture 中的 `client.scope`。
6. **测试**：覆盖"带 scope 时下发""不带 scope 时不下发""scope 之间不串数据"三类用例，
   见 `test/authx_web/oidc_routes_test.exs`。
7. **文档**：更新本文与 `docs/oidc-client-management.md` 中的 scope 列表。

---

## 9. 当前限制

- 授权请求必须携带 `nonce`；尚未实现 `prompt`、`max_age`、`claims` 参数和
  请求对象（`request` / `request_uri`）。
- 只支持 Authorization Code + S256 PKCE；不签发 OIDC refresh token，也不提供
  OIDC 全局注销。
- `sub` 使用 `public` subject（用户 ID 原值），未实现 pairwise subject。
- `profile` 目前只下发 `updated_at`，因为用户模型没有姓名、昵称、头像等字段。
- `.well-known/openid-configuration` 的 scope/claim 列表为手写，修改时需人工保持一致。

生产化门禁见 [OIDC 生产化与上线计划](oidc-production.md)。
