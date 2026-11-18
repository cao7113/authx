# OIDC client demo

## 当前实现

Authx 为开发、测试和显式启用的本地试运行提供受限的 OIDC authorization
code + S256 PKCE 流程；`demo/` 是独立的 Phoenix、Ash 和 AshAuthentication 应用。demo
使用自己的数据库和会话，不直接读取 Authx 数据库或接收用户密码。

Authx 的 discovery、JWKS、授权、token 和 UserInfo 端点分别位于
`/.well-known/openid-configuration`、`/oidc/jwks`、`/oidc/authorize`、
`/oidc/token` 和 `/oidc/userinfo`。ID Token 使用 RS256，包含签发方、
用户 ID、客户端 audience、过期时间和请求绑定的 nonce；申请 `email`
scope 时还包含 email 和 email_verified，申请 `profile` scope 时包含
updated_at。UserInfo 使用独立 audience 的
access token，且只在授权对应 scope 时返回相应 claim。scope 详情见
[OIDC Scope 实现说明](oidc-scopes.md)。

demo 的 AshAuthentication OIDC strategy 验证 ID Token，并按 `(issuer, sub)`
关联本地用户；email 是可更新属性，不按 email 自动合并账号。退出 demo
只结束 demo 会话，不退出 Authx。

## 本地启动

前提：本仓库依赖已准备好，PostgreSQL 可用，4000 和 4001 端口空闲。
demo 与根项目共享 `deps/` 和根 `mix.lock`，但有独立的 `_build/`、
数据库和应用进程；它不会自动下载依赖。

1. 在根目录准备 Authx 数据库、开发用户和本地 demo 客户端：

   ```sh
   mix dev.setup
   ```

   该命令创建数据库、执行迁移、创建开发用户，并在给开发管理员授予
   developer 身份后注册 demo 客户端。**它会重置现有开发账号的密码**，
   详见根目录 README。已有数据库时也可分别执行 `mix ecto.migrate` 和
   `mix dev.seed`。

2. demo 客户端由 `config/dev.exs` 的 `:demo_client_app` 固定配置，默认 id
   为 `00000000-0000-7000-8000-000000000001`，默认回调为
   `http://localhost:4001/auth/user/authx/callback`，可用
   `AUTHX_DEMO_CALLBACK` 覆盖。重复执行 `mix dev.seed` 会复用并校验该
   客户端。它归属于 `mix dev.seed` 授予的开发者身份（开发环境管理员）。
   动态客户端注册（DCR）与 CIMD 均已关闭：客户端必须归属某个 developer，
   只能由开发者身份创建，见 [OIDC 客户端管理](oidc-client-management.md)。

3. 在根目录启动 Authx：

   ```sh
   mix phx.server
   ```

4. 在另一个终端准备并启动 demo：

   ```sh
   cd demo
   mix ecto.create
   mix ecto.migrate
   AUTHX_CLIENT_ID=00000000-0000-7000-8000-000000000001 mix phx.server
   ```

5. 打开 `http://localhost:4001`，点击「使用 Authx 登录」。在 Authx
   登录并同意授权后，demo 显示统一用户 ID 和 email。退出 demo 后再次
   登录应显示同一 ID；如果 Authx 会话和授权仍有效，可能不会再次要求
   登录或同意。

可通过 `AUTHX_ISSUER`、demo 的 `AUTHX_REDIRECT_URI` 和 `mix dev.seed` 的
`AUTHX_DEMO_CALLBACK` 调整本地地址；三者必须与实际监听地址和完整回调
一致。demo 的 `DEMO_DEV_DATABASE` 可覆盖其开发数据库名。

## 登录技术流程

参与方是浏览器、demo 客户端（`localhost:4001`）和 Authx（`localhost:4000`）。
这是 OIDC Authorization Code + S256 PKCE 流程：用户凭据只提交给 Authx，
demo 不读取或保存 Authx 密码；授权码通过浏览器返回，令牌交换则由 demo
服务端直接请求 Authx。

1. **发起登录。** 首页的「使用 Authx 登录」链接请求
   `GET /auth/user/authx`。AshAuthentication OIDC strategy 从运行时配置读取
   `AUTHX_CLIENT_ID`、`AUTHX_ISSUER` 和 `AUTHX_REDIRECT_URI`，并通过 Authx 的
   `/.well-known/openid-configuration` 获取协议端点。回调 URI 由
   `AUTHX_REDIRECT_URI` 加上 `/user/authx/callback` 组成，默认是
   `http://localhost:4001/auth/user/authx/callback`。

2. **建立授权请求。** demo 生成一次性 `state`、`nonce` 和 PKCE
   `code_verifier`，将这些回调校验参数保存在自己的浏览器 session 中；
   将 `code_verifier` 的 S256 摘要作为 `code_challenge`。随后浏览器被重定向到
   Authx 的 `/oidc/authorize`，请求 `response_type=code`、`scope=openid email`、
   `code_challenge_method=S256`，并带上注册的 client ID、完整回调 URI、
   `state` 和 `nonce`。

3. **在 Authx 登录和授权。** Authx 检查客户端、精确匹配的回调 URI、scope、
   response type、grant type、PKCE 参数及必需的 nonce。若用户尚未登录，
   Authx 暂存原授权请求并跳转到 `/sign-in`；密码或 magic link 认证成功后，
   再回到原授权请求。demo 看不到这一步的凭据。用户已有对该客户端及 scope
   的 consent 时可以跳过授权页；否则 Authx 显示 consent，拒绝时返回
   `access_denied`，批准时记录 consent。

4. **返回一次性授权码。** Authx 将授权码和用户、客户端、回调 URI、scope、
   PKCE challenge、nonce 及过期时间关联保存，然后重定向浏览器到 demo 回调，
   附上 `code`、原 `state` 和 issuer。授权码短期有效且只能消费一次。

5. **服务端兑换令牌。** demo 回调校验浏览器 session 中保存的 `state`，然后
   由 demo 服务端向 Authx 的 `/oidc/token` 提交授权码、相同的回调 URI、
   client ID 和 `code_verifier`。该客户端是预注册的公开客户端，使用
   `token_endpoint_auth_method=none`，不发送 client secret。Authx 检查授权码
   未过期、未使用且绑定信息一致，并校验 `code_verifier` 对应的 S256
   challenge；通过后消费授权码并返回 access token 和 ID Token。

6. **验证身份并关联 demo 用户。** demo 的 OIDC strategy 根据 discovery 中的
   JWKS 验证 RS256 ID Token，并检查 issuer、audience、有效期和 session 中的
   nonce。当前流程从已验证的 ID Token claims 取得 `sub` 和 email；申请
   `email` scope 时 Authx 才签发 email 与 `email_verified` claim。授权服务器也
   提供 `/oidc/userinfo`，但此 demo 的身份建立使用 ID Token claims。
   demo 以 `(issuer, sub)` upsert 本地用户，email 可更新但不作为账号合并键；
   因此相同 email、不同 issuer 或 subject 仍是不同身份。

7. **建立本地会话。** 用户记录成功建立或更新后，demo 轮换 session ID、
   将用户写入自己的 session 并重定向首页。后续请求由 demo 的
   `load_from_session` 恢复 `current_user`；页面显示本地关联身份的 subject、
   email 和 issuer。Authx 与 demo 使用各自的数据库和 session，互不共享登录
   cookie。

点击「退出当前应用」只清除 demo 的 session 并轮换 session ID，不会撤销
Authx session 或已授予的 consent；因此再次登录时，Authx 可能直接返回授权结果。

### `token_endpoint_auth_method` 的含义

该值描述客户端调用 token endpoint（本 demo 中是 `/oidc/token`）时如何证明
自己的客户端身份；它不是用户登录方式。OAuth/OIDC provider 会通过
discovery 的 `token_endpoint_auth_methods_supported` 公布自己接受的方式，
注册客户端时必须选择 provider 实际支持的值。PKCE 是另一层保护：它把授权码
绑定到发起请求的客户端，不能把机密客户端的凭据保护责任转移给 PKCE。

Authx 当前 discovery 只公布 `none`，demo 注册任务也将客户端注册为
`token_endpoint_auth_method=none`，所以**下面其他方式只是常见标准选项，并
不代表当前 Authx demo 支持它们**：

- `none`：不在 token 请求中发送 client secret。适用于无法安全保存秘密的公开
  客户端，例如原生移动应用、浏览器端应用；应同时使用 PKCE、严格匹配回调
  URI 等措施。当前 demo 客户端使用此方式，发送 client ID 和 PKCE verifier，
  不发送 client secret。
- `client_secret_basic`：用 HTTP Basic Authorization header 发送 client ID
  和 client secret。常见于能在服务端保管 secret 的传统 Web 后端；通常是
  shared-secret 方式中的首选。
- `client_secret_post`：在 token 请求的表单正文中发送 client ID 和
  client secret。用于 provider 要求此方式或不支持 Basic 的情况；secret 更
  容易进入请求体日志，通常不优先于 `client_secret_basic`。
- `client_secret_jwt`：客户端用共享 secret 签署短期 JWT assertion，并在
  token 请求中提交 assertion。适用于双方已安全配置共享密钥、需要用签名断言
  替代直接传送 secret 的服务端集成。
- `private_key_jwt`：客户端用自己的私钥签署短期 JWT assertion，provider
  预先登记对应公钥。适用于可以管理私钥、希望避免共享 secret 的服务端集成；
  需要妥善保护和轮换私钥。
- `tls_client_auth`、`self_signed_tls_client_auth`：基于双向 TLS 客户端证书
  认证，常见于有证书签发、部署和轮换能力的高信任服务端环境；不是当前 demo
  暴露的选项。


## 验证

根目录执行 `mix precommit`；demo 目录执行 `mix precommit`。根目录的
OIDC 路由测试覆盖 discovery、公钥、nonce、PKCE、授权码重放、用户信息、
email scope 和错误回调；demo 测试覆盖身份关联与 email 更新。

## 限制和生产化

- 这是**本地 demo**，生产路由默认关闭。仅支持预注册的公开客户端
  `none`，不支持客户端密钥认证、OIDC refresh token 或全局注销。
- 默认 demo 的 RS256 私钥在进程内生成，重启后公钥改变。本地生产模式可
  加载固定私钥文件，但尚未实现密钥轮换，不应对外用于正式生产。
- 生产启用前仍需独立安全审查、标准兼容性测试、HTTPS、持久密钥及轮换、
  客户端管理、速率限制、审计和注销语义。不要将开发凭据用于生产。
- 分阶段实施和上线门禁见 [OIDC 生产化与上线计划](oidc-production.md)。
- 本地动态注册和管理员职责见 [OIDC 客户端管理](oidc-client-management.md)。
