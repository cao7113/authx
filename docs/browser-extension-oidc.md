# 浏览器插件接入 Authx OIDC

> 状态：设计参考。本文区分「插件使用 Authx 登录」（当前支持）与「插件直接使用
> Authx access token 调用业务 API」（当前不支持）。实现前请先阅读
> [OIDC 客户端认证与公开客户端威胁模型](oidc-client-authentication.md)。

面向场景：某个接入 Authx 的客户端应用希望提供一个浏览器插件（Chrome /
Edge / Firefox），用户登录后在插件中调用该应用的 API。

---

## 1. 结论摘要

| 能力 | 当前是否支持 | 说明 |
|---|---|---|
| 插件作为公开客户端使用 Authorization Code + S256 PKCE 登录 Authx | **支持** | 回调使用浏览器扩展的 `chromiumapp.org` / `extensions.allizom.org` 域名 |
| 插件用 Authx ID Token 建立应用身份 | **支持** | 建议由应用后端验证 ID Token 后签发自己的 API 凭据 |
| 插件用 Authx access token 调用 Authx `/oidc/userinfo` | **支持** | access token 的 audience 是 Authx 的 UserInfo resource |
| 插件用 Authx access token 直接调用业务 API | **不支持** | Authx 当前只配置单 resource，`aud` 固定为 Authx UserInfo；无 refresh token、无 token 撤销 |
| 插件长期免登录（refresh token） | **不支持** | Authx discovery 仅公布 `authorization_code`，不签发 refresh token |

推荐架构：**插件用 OIDC 登录 + 应用后端验证 ID Token + 后端签发自己的 API
token**。不要让业务 API 直接接受 Authx access token。

---

## 2. 两层信任模型

浏览器插件无法安全保存 `client_secret`，因此永远是公开客户端。公开客户端
的 `client_id` 不是凭据，安全边界是：

1. 注册回调精确匹配；
2. S256 PKCE；
3. `state` / `nonce`；
4. 用户在 Authx 登录并 consent；
5. 授权码一次性、短期有效。

登录成功后，插件得到的是 **Authx 身份**（ID Token 中的 `iss` + `sub` 与
email）。业务 API 的授权应当由应用自己决定，而不是把 Authx access token
当作通用 API 凭据。

---

## 3. 模型 A（推荐）：插件登录 + 后端签发 API token

```text
插件（service worker / background）
  │ 1. launchWebAuthFlow(/oidc/authorize, PKCE+state+nonce)
  ▼
Authx
  │ 2. 用户登录 + consent
  ▼
插件
  │ 3. 收到 redirect: code + state，校验 state
  │ 4. POST /oidc/token（code + code_verifier + redirect_uri）
  ▼
Authx
  │ 5. 返回 access_token + id_token
  ▼
插件
  │ 6. 把 id_token + nonce 交给应用后端
  ▼
应用后端
  │ 7. 用 Authx JWKS 验证签名、iss、aud、exp、nonce
  │ 8. 按 (issuer, sub) 关联应用用户
  │ 9. 签发应用自己的短效 API token（或建立插件会话）
  ▼
插件 ──应用 API token──> 应用 API
```

### 3.1 后端校验清单

应用后端收到插件提交的 ID Token 时必须：

- 使用 Authx discovery 中的 `jwks_uri` 获取公钥，验证 RS256 签名；
- 校验 `iss` 等于配置的 Authx issuer；
- 校验 `aud` 等于该应用的 `client_id`；
- 校验 `exp` / `iat`，允许小幅时钟偏差；
- 校验 `nonce` 等于插件本次授权请求生成的值（由插件一并提交）；
- 按 `(iss, sub)` 关联本地用户，**不要仅按 email 合并账号**；
- 不要仅凭插件传来的 `client_id`、`sub` 或 email 文本建立信任。

### 3.2 应用 API token

由应用后端签发，可以是：

- 短效 Bearer JWT（自带 `aud`、`scope`、过期时间），或
- 不透明的服务端会话 token，配合数据库撤销。

插件退出、卸载或被禁用时，应用后端可以立即撤销自己的 token；Authx 侧无需
感知业务授权。这种分层让插件与 Web 端共享同一套 Authx 身份，同时保持业务
API 的独立授权、撤销和审计。

### 3.3 为什么不让 API 直接接受 Authx token

- Authx access token 的 `aud` 是 `oidc_resource_url`（默认
  `http://localhost:4000/oidc/userinfo`），不是你的业务 API；
- Authx 当前没有把第三方 API 注册为 resource 的配置入口（OIDC server 使用
  单 `resource_url`）；
- Authx 当前不签发 refresh token，也不提供 token 撤销接口；
- 业务 API 若直接接受，会把 Authx 的可用性和安全边界与所有客户端耦合。

---

## 4. 模型 B（未来）：业务 API 作为 Authx resource

如果确实需要“插件拿 Authx token 直接调业务 API”，需要先扩展 Authx：

1. **多 resource 支持**：把 OIDC server 从 `resource_url` 改为 `resources`
   配置，为每个业务 API 注册独立 resource 与 scope（上游已支持该配置形态，
   Authx 尚未启用）。
2. **API 端校验**：业务 API 验证 JWT 的 `iss`、`aud`（必须等于自己的
   resource 标识）、`exp`、`scope`，并实现签名密钥缓存与轮换。
3. **refresh token**：在 discovery 与 token 响应中启用
   `refresh_token` grant，并实现安全存储、轮换、重放检测和撤销。
4. **撤销与下线**：提供 token 撤销/内省接口，或在 access token 中加入可撤销
   的会话标识。
5. **速率限制与审计**：按客户端、用户、IP 维度限流，记录 token 使用。

在这些能力完成前，不建议任何业务 API 接受 Authx access token。

---

## 5. 插件登录实现细节

### 5.1 Chrome / Edge（Manifest V3）

所需权限：`identity`、`storage`，以及 Authx issuer 的 `host_permissions`。

```json
{
  "manifest_version": 3,
  "name": "My App Helper",
  "version": "1.0.0",
  "permissions": ["identity", "storage"],
  "host_permissions": ["https://authx.example.com/*"],
  "background": {
    "service_worker": "background.js",
    "type": "module"
  }
}
```

回调地址：

```js
const redirectUri = chrome.identity.getRedirectURL("authx");
// https://<extension-id>.chromiumapp.org/authx
```

发起登录：

```js
const verifier = base64url(crypto.getRandomValues(new Uint8Array(64)));
const digest = await crypto.subtle.digest(
  "SHA-256",
  new TextEncoder().encode(verifier)
);
const challenge = base64url(new Uint8Array(digest));

const state = base64url(crypto.getRandomValues(new Uint8Array(32)));
const nonce = base64url(crypto.getRandomValues(new Uint8Array(32)));

// MV3 的 service worker 可能在授权窗口打开期间被回收，
// 因此 verifier/state/nonce 必须持久化到 storage.session。
await chrome.storage.session.set({ authx: { verifier, state, nonce } });

const url = new URL("https://authx.example.com/oidc/authorize");
url.search = new URLSearchParams({
  client_id: CLIENT_ID,
  redirect_uri: redirectUri,
  response_type: "code",
  scope: "openid email",
  state,
  nonce,
  code_challenge: challenge,
  code_challenge_method: "S256"
}).toString();

const responseUrl = await chrome.identity.launchWebAuthFlow({
  url: url.toString(),
  interactive: true
});
```

回调处理：

```js
const params = new URL(responseUrl).searchParams;
const saved = (await chrome.storage.session.get("authx")).authx;

if (params.get("state") !== saved.state) throw new Error("state mismatch");
if (params.get("error")) throw new Error(params.get("error"));

const code = params.get("code");
```

令牌交换（在 service worker 中执行）：

```js
const response = await fetch("https://authx.example.com/oidc/token", {
  method: "POST",
  headers: { "content-type": "application/x-www-form-urlencoded" },
  body: new URLSearchParams({
    grant_type: "authorization_code",
    client_id: CLIENT_ID,
    code,
    redirect_uri: redirectUri,
    code_verifier: saved.verifier
  })
});

const { access_token, id_token } = await response.json();
await chrome.storage.session.remove("authx");
```

随后把 `id_token` 和 `saved.nonce` 提交给应用后端，由后端验证并签发应用 API
token。

### 5.2 Firefox

Firefox 使用 `browser.identity.launchWebAuthFlow`，并在 manifest 中声明
`identity` 权限。建议显式固定扩展 ID：

```json
{
  "browser_specific_settings": {
    "gecko": {
      "id": "my-app-helper@example.com"
    }
  },
  "permissions": [
    "identity",
    "storage",
    "https://authx.example.com/*"
  ]
}
```

```js
const redirectUri = browser.identity.getRedirectURL();
// https://<add-on-id>.extensions.allizom.org/
```

Firefox 的 Manifest V3 与 Chrome 在 background script / service worker 的
生命周期上存在差异，PKCE verifier、state、nonce 同样应持久化，不能只放在
内存变量中。

### 5.3 扩展 ID 必须稳定

Authx 的 `redirect_uri` 是**精确匹配**的，因此回调域名中的扩展 ID 必须稳定：

- **Chrome**：商店安装由商店分配固定 ID；未打包开发时，在 manifest 中固定
  `key`，否则不同路径/机器的扩展 ID 不同。
- **Firefox**：显式设置 `browser_specific_settings.gecko.id`；临时加载且未
  设置 ID 时，回调 URI 可能随安装变化。
- **多环境**：开发版、测试版、商店版可能使用不同扩展 ID，需要分别登记
  redirect URI，或统一固定 ID。

建议在 Authx 客户端上登记多个精确回调，例如：

```text
https://<dev-extension-id>.chromiumapp.org/authx
https://<store-extension-id>.chromiumapp.org/authx
```

### 5.4 授权请求参数

Authx 当前要求：

| 参数 | 值 |
|---|---|
| `client_id` | 插件对应的客户端注册 id |
| `redirect_uri` | 与注册值完全一致 |
| `response_type` | `code` |
| `scope` | 必须包含 `openid`，可选 `email`（客户端白名单内） |
| `state` | 高熵随机值，回调校验 |
| `nonce` | 高熵随机值，写入 ID Token |
| `code_challenge` | S256(PKCE verifier) |
| `code_challenge_method` | `S256` |

Authx 不接受 `request`、`request_uri`、`prompt`、`max_age`、`claims` 参数。

### 5.5 令牌交换注意事项

- token 端点需要 `code`、`client_id`、`redirect_uri`、`code_verifier`；
- 不使用 `client_secret`；
- 授权码一次性，失败时不会消费（可重试有效期内）；
- 当前 Authx 不签发 refresh token，access token 默认有效期 1 小时，过期后
  需要重新发起授权流程；
- Authx token 端点当前**没有 CORS 响应头**。Chrome/Firefox 扩展在 service
  worker / background 中配合 `host_permissions` 可以跨域请求；普通网页或
  content script 中的 `fetch` 可能被 CORS 拦截。若无法保证扩展环境，建议
  由应用后端代为交换令牌，或为扩展来源增加 CORS 白名单。

---

## 6. Authx 客户端注册

为插件单独注册一个公开客户端（推荐），或与 Web 端共用客户端但登记多个
redirect URI。

| 字段 | 建议值 |
|---|---|
| `client_name` | 例如 `My App Browser Extension` |
| `redirect_uris` | `https://<extension-id>.chromiumapp.org/authx` 等精确值 |
| `grant_types` | `["authorization_code"]` |
| `response_types` | `["code"]` |
| `token_endpoint_auth_method` | `"none"` |
| `scope` | `"openid email"`（按需裁剪） |

当前注册入口：

- 本地开发：`mix dev.seed` 配置的固定客户端，或开发者控制台（待实现）；
- 生产：由 developer 身份创建并归属某个 developer（见
  [OIDC 客户端管理](oidc-client-management.md)）。

注意：回调必须是 HTTPS 且有 host、无 fragment（loopback HTTP 仅用于本地
开发）；`chromiumapp.org` / `extensions.allizom.org` 的 HTTPS 地址满足规则。

---

## 7. 当前 Authx 的限制

| 限制 | 对插件的影响 |
|---|---|
| 只支持公开客户端 `none` | 插件不能使用 client secret，必须 PKCE |
| 单 resource，access token `aud` 固定为 Authx UserInfo | 不能直接拿 access token 调业务 API |
| discovery 只公布 `authorization_code` | 没有 refresh token，插件需定期重新授权 |
| 无 token 撤销 / 内省 | 插件卸载、用户退出后，已签发 token 在过期前仍有效 |
| 无 CORS | token 交换需走扩展后台或应用后端 |
| 无速率限制 / 审计 | 授权与 token 端点可能被滥用，生产前需补齐 |
| 客户端凭据错误语义待规范 | 引入机密客户端时需一并修正 401/`WWW-Authenticate` |

---

## 8. 安全清单

发布前逐项确认：

- [ ] 插件不保存 `client_secret`；使用 `none` + S256 PKCE。
- [ ] `state`、`nonce`、`code_verifier` 每次授权重新生成，且不重复使用。
- [ ] verifier/state/nonce 存在 `storage.session`（或带 TTL 的安全存储），
      能承受 service worker 被回收。
- [ ] 回调后先校验 `state` 再处理 `code`，错误参数直接拒绝。
- [ ] ID Token 由应用后端验证签名、iss、aud、exp、nonce；插件自身不做
      “只解析不验签”的信任判断。
- [ ] 应用 API 只接受应用自己签发的 token，不接受 Authx access token。
- [ ] token 不写入日志、不进入 content script、不通过 `window.postMessage`
      广播。
- [ ] 插件权限最小化：只申请必要的 `identity`、`storage` 和目标 API 的
      `host_permissions`。
- [ ] 扩展 ID 在开发/商店环境固定，并登记对应 redirect URI。
- [ ] 退出插件时清理本地 token，并调用应用后端的撤销接口。
- [ ] 应用后端对 ID Token 验签结果做缓存时，缓存键包含 `kid`，并支持
      JWKS 轮换。
- [ ] 监控授权失败、state/nonce 失败、token 交换失败和异常频率。

---

## 9. 测试清单

**协议与负向**

- 正确授权码 + verifier → 成功；
- 错误 verifier / 复用授权码 / 过期授权码 → `invalid_grant`；
- `state` 不匹配 / 缺失 → 插件拒绝；
- `nonce` 不匹配 → 后端拒绝；
- 错误 `redirect_uri` → Authx `invalid_request`；
- 未登记 scope / 缺少 `openid` → 授权失败；
- 携带 `client_secret` 或 Basic 头 → Authx 拒绝。

**扩展环境**

- Chrome MV3 service worker 被回收后仍能完成回调（verifier 持久化）；
- Firefox 临时加载与固定 ID 两种情况的 redirect URI 一致；
- 扩展更新、重新安装、切换浏览器配置后仍能登录（ID 稳定性）；
- 无 CORS 环境下 token 交换路径可用（后台 fetch 或后端代换）。

**应用侧**

- ID Token 签名/iss/aud/exp/nonce 负向用例；
- 同一 `sub` 重复登录关联同一应用用户；
- 撤销应用 token 后 API 立即拒绝；
- 应用 API 不接受 Authx access token（aud 不匹配）。

---

## 10. 分阶段建议

1. **现在**：按模型 A 实现插件登录 + 应用后端验证 ID Token + 应用自己的
   API token。该路径不需要修改 Authx。
2. **生产前**：补齐速率限制、审计、日志脱敏和错误语义；确定扩展 ID 与
   redirect URI 的发布流程。
3. **需要长期会话时**：推动 Authx 启用 refresh token（上游已实现轮换与重放
   检测，Authx 尚未在 discovery/响应中开放）并增加撤销能力。
4. **需要插件直接调业务 API 时**：先完成多 resource 注册与 API 端 JWT
   校验，再评估是否值得放弃“后端签发应用 token”的分层模型。

---

## 11. 参考

- Chrome Identity API：`chrome.identity.launchWebAuthFlow`、
  `chrome.identity.getRedirectURL`
- Firefox Identity API：`browser.identity.launchWebAuthFlow`、
  `browser.identity.getRedirectURL`
- RFC 6749 / OAuth 2.1：Authorization Code、PKCE、客户端认证
- RFC 7636：PKCE
- RFC 8707：Resource Indicators（audience 绑定）
- RFC 9068：JWT Profile for OAuth 2.0 Access Tokens
- OpenID Connect Core 1.0：ID Token 校验、nonce
- Authx 文档：[OIDC client demo](client-demo.md)、
  [OIDC 客户端管理](oidc-client-management.md)、
  [OIDC 客户端认证与公开客户端威胁模型](oidc-client-authentication.md)、
  [OIDC 生产化与上线计划](oidc-production.md)
