# OAuth 2.1 与 OpenID Connect (OIDC) 架构说明

Authx 同时支持标准 **OAuth 2.1** 与 **OpenID Connect (OIDC 1.0)**。为了清晰界定协议边界、避免根目录蔓延，所有与协议存储和授权服务器相关的实现均收敛在 `Authx.Oauth` 领域（`lib/authx/oauth/`）下。

---

## 核心组件与分工

Authx 内有两个授权服务器配置模块，分别应对不同的场景：

```text
               ┌─────────────────────────────────────────────────────┐
               │                     Authx.Oauth                     │
               │  (Client, Consent, AuthorizationCode, RefreshToken) │
               └──────────────────────────┬──────────────────────────┘
                                          │
                  ┌───────────────────────┴───────────────────────┐
                  ▼                                               ▼
     ┌────────────────────────┐                      ┌────────────────────────┐
     │   Authx.Oauth.Server   │                      │ Authx.Oauth.Oidc.Server│
     │      (OAuth 2.1)       │                      │        (OIDC 1.0)      │
     ├────────────────────────┤                      ├────────────────────────┤
     │ • 面向 API/资源授权    │                      │ • 面向用户身份认证 (IdP)│
     │ • Scope: ["mcp"]       │                      │ • 3 个 scope           │
     │ • 对外路由: /oauth/*   │                      │ • 对外路由: /oidc/*, discovery│
     │ • 动态注册: 关闭 (DCR) │                      │ • 动态注册: 关闭 (DCR/CIMD) │
     │ • 自动挂载协议路由     │                      │ • 配合 Oidc.Keys 签发Token   │
     └────────────────────────┘                      └────────────────────────┘
```

### 1. `Authx.Oauth.Server` (OAuth 2.1 授权服务器)
- **定位**：纯粹的 OAuth 2.1 资源授权端点，主要服务于 API 访问、MCP (Model Context Protocol) 等受限客户端凭据流。
- **协议路由**：由 `AshAuthentication.Phoenix.Oauth2Server.ProtocolRouter` 在 `/oauth` 路径自动转发（`/oauth/authorize`, `/oauth/token` 等）。
- **运行门禁**：仅在启用 `:oauth2_demo_routes` 时挂载，默认不对生产公开。
- **配置特点**：
  - `scopes: ["mcp"]`
  - `dcr_enabled?: false`（不允许客户端未授权动态注册）

### 2. `Authx.Oauth.Oidc.Server` (OpenID Connect 身份提供商)
- **定位**：面向接入 Authx 的第三方或自研客户端（RP, Relying Party），作为独立身份提供商（IdP）验证用户身份。
- **协议路由**：由 `AuthxWeb.OidcController` 显式控制和路由：
  - `/.well-known/openid-configuration` (Discovery 元数据)
  - `/.well-known/jwks.json` (公钥发布)
  - `/oidc/authorize` (授权与同意界面交互)
  - `/oidc/token` (代码换取 Token 及 ID Token)
  - `/oidc/userinfo` (Bearer 认证获取最终用户 claims)
- **密钥基础设施**：配合 `Authx.Oauth.Oidc.Keys`（GenServer 管理的 RS256 密钥对），负责对 OpenID Connect 的 `id_token` 执行非对称加密签名。
- **配置特点**：
  - `scopes: ["openid", "email", "profile"]`，scope 语义、校验路径与 claim 下发见
    [OIDC Scope 实现说明](oidc-scopes.md)
  - `dcr_enabled?: false`、`cimd_enabled?: false`：客户端必须归属于某个 developer，只能由开发者身份创建，见 [OIDC 客户端管理](oidc-client-management.md)

---

## 为什么分为两个 Server？是否功能重复？

1. **协议目的不同**：
   - OAuth 2.1 的目标是**授权（Authorization）**——让第三方应用代表用户调用某个特定的 API（如 MCP）；
   - OIDC 1.0 的目标是**身份认证（Authentication）**——让第三方应用安全地确认“当前操作用户是谁”，并获得签名的 `id_token` 与用户资料。
2. **安全模型与凭据不同**：
   - `Authx.Oauth.Server` 签发的是针对指定 resource 的 access_token；
   - `Authx.Oauth.Oidc.Server` 必须支持非对称加密签名（RS256）的 ID Token、JWKS 端点，以及遵循 OIDC Core 规范的 discovery 元数据。
3. **共享底层数据模型**：
   两者共享 `Authx.Oauth` 领域的四大基础存储资源：
   - `Client`：已登记的客户端应用（包含名字、回调地址、授权类型等）；
   - `Consent`：最终用户对具体 Client 授予的 Scope 记录；
   - `AuthorizationCode`：端点间流转的短期授权码；
   - `RefreshToken`：长期轮转凭证。

---

## 领域目录结构

```text
lib/authx/oauth/
├── authorization_code.ex   # Authx.Oauth.AuthorizationCode
├── client.ex               # Authx.Oauth.Client
├── consent.ex              # Authx.Oauth.Consent
├── refresh_token.ex        # Authx.Oauth.RefreshToken
├── server.ex               # Authx.Oauth.Server (OAuth 2.1)
└── oidc/
    ├── keys.ex             # Authx.Oauth.Oidc.Keys (RS256 签名)
    └── server.ex           # Authx.Oauth.Oidc.Server (OIDC 1.0)
```

所有与应用登记、OAuth 授权码与令牌生成、OIDC 登录握手的代码均完整封装在该目录下，与 `Authx.Accounts`（用户身份）和 `Authx.Developers`（应用开发者资格）保持严格单向解耦。
