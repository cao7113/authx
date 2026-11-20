# authx-foo 的 Ash 相关依赖说明

> 对象：`_local/authx-foo`，Authx 的 OIDC 客户端示例应用。
> 目的：说明每个 Ash 相关依赖在“作为 Authx 客户端”这一场景下的实际作用，
> 以及哪些是业务必需、哪些只是开发工具。
> 登录方案本身见 [Authx Foo 接入 Authx OIDC](authx-foo-oidc-client.md)。

## 1. 速览

| 库 | 层次 | 在本项目中的作用 | 业务必需 | 可直接删除 |
|---|---|---|---|---|
| `ash` | 核心 | 定义 User / Token / UserIdentity 资源、动作与策略 | 是 | 否 |
| `ash_postgres` | 数据层 | 资源落库、迁移、resource snapshot、Repo | 是 | 否 |
| `ash_authentication` | 认证核心 | OIDC 策略、ID Token 校验、token 签发、Plug 与会话 | 是 | 否 |
| `ash_authentication_phoenix` | 认证 Web 层 | 登录/登出/回调路由、默认登录 UI、LiveView 会话 | 是 | 否 |
| `ash_phoenix` | Phoenix 集成 | 仅 dev 下的 codegen 状态检查 | 否 | 仅可删显式声明（仍被传递依赖引入） |
| `ash_admin` | 管理后台 | 所有环境的 `/admin`，以登录 User 为 actor | 否 | 是（连同 `/admin` 路由） |

版本快照（`mix.lock`）：`ash 3.37.6`、`ash_postgres 2.16.0`、
`ash_phoenix 2.3.26`、`ash_authentication 4.15.1`、
`ash_authentication_phoenix 2.17.4`、`ash_admin 1.4.0`。

## 2. 各库说明

### ash

Ash 的框架核心：声明式资源（attribute / action / identity / policy）、
领域（domain）、扩展机制与授权。它本身不关心 Web，也不关心认证。

本项目中：

- `AuthxFoo.Accounts.User`、`Token`、`UserIdentity` 三个资源的声明。
- `AuthxFoo.Accounts` 领域（`config :authx_foo, ash_domains: [...]`）。
- `Ash.Policy.Authorizer` 与 `bypass AshAuthentication.Checks.AshAuthenticationInteraction`，
  让认证框架内部读写 token / 用户时绕过普通策略。
- `upsert? upsert_identity :unique_email`：OIDC 回调按 email upsert 本地用户。
- 与认证相关的扩展声明（`extensions: [AshAuthentication]` 等）都挂在这里。

### ash_postgres

`ash` 的 PostgreSQL 数据层，提供 `AshPostgres.Repo`、迁移生成与 resource
snapshot。是“资源定义”和“数据库表”之间的桥梁。

本项目中：

- `AuthxFoo.Repo` 基于 `AshPostgres.Repo`。
- `users`、`user_identities`、`tokens` 三张表对应 `priv/repo/migrations/`，
  schema 快照在 `priv/resource_snapshots/repo/`。
- 修改资源后需要用 Ash 的 codegen 任务更新迁移/快照（见 `ash_phoenix` 一节）。

### ash_authentication

认证核心库，不依赖 Phoenix。职责包括：

- **策略（strategy）**：本项目的 `oidc :authx` 策略——读取 discovery 文档、
  生成 state / nonce / PKCE、用授权码换取 token、校验 ID Token 的
  issuer / audience / 时效 / nonce。
- **token 子系统**：`TokenResource` 扩展、`GenerateTokenChange`、
  签名密钥（`AuthxFoo.Secrets` 实现 `AshAuthentication.Secret`）。
- **身份关联**：`AshAuthentication.UserIdentity` 扩展，用
  `(strategy, uid)` 保存 Authx 的 `sub`，与本地用户一一对应。
- **Plug 与会话**：`load_from_session` / `load_from_bearer` /
  `store_in_session`，以及 `AshAuthentication.Supervisor`（在
  `AuthxFoo.Application` 中启动）。

一句话：**OIDC 的协议细节全部在这里**，没有它就没有真正的 OIDC 登录。

### ash_authentication_phoenix

上一节库的 Phoenix / LiveView 适配层，提供“用户看得见”的部分：

- `AshAuthentication.Phoenix.Router` 提供的路由宏：`auth_routes`
  （`/auth/authx/callback` 等回调端点）、`sign_in_route`、`sign_out_route`、
  `reset_route`、`confirm_route`、`magic_sign_in_route`、
  `ash_authentication_live_session`。
- `AshAuthentication.Phoenix.Controller`：`AuthController` 的接入点与
  `store_in_session/2`。
- `AshAuthentication.Phoenix.LiveSession`：嵌套 LiveView 中恢复
  `current_user`。
- `AshAuthentication.Phoenix.Overrides` + 内置 `Components`：
  `/sign-in` 页面的默认 UI（“使用 Authx 登录”按钮由 OIDC 策略自动生成）。

本项目的 `/sign-in` 是框架默认页面，只通过 `AuthxFooWeb.AuthOverrides`
做样式覆盖。

### ash_phoenix

Ash 的通用 Phoenix 集成（表单、LiveView 数据绑定、codegen 检查）。本项目
**没有使用其表单/LiveView 能力**，唯一的直接引用是：

- `plug AshPhoenix.Plug.CheckCodegenStatus`（仅在 `code_reloading?` 即 dev
  下启用）：请求时检查是否有未生成的 Ash codegen，避免用过期 schema 调试。
- `.formatter.exs` 的 `import_deps`。

注意：`ash_authentication_phoenix` 与 `ash_admin` 都把它列为**非 optional**
依赖，所以即使删掉 `mix.exs` 中的显式声明，它依然会被下载和编译。删除显式
声明只会失去上面的 dev 检查，不会减少依赖树。

### ash_admin

Ash 资源的通用管理后台，按 domain 自动生成增删改查界面。

本项目中：

- `AuthxFoo.Accounts` 的 `extensions: [AshAdmin.Domain]`。
- `/admin` 在**所有环境**挂载，入口在顶部导航的 Admin 链接。
- 请求进入 `/admin` 时，`router.ex` 的 `:put_admin_actor` 会把当前登录用户
  的 id 写入 AshAdmin 读取的 actor cookie，因此后台以该 User 为 actor 运行。
- `User` 资源声明了 `AshAdmin.Resource` 扩展与 `admin do actor? true end`；
  `User` / `Token` 的 policy 为演示方便整体放开。

与 OIDC 客户端功能无关，是调试工具，可按需移除。由于演示环境对 `/admin`
不做访问控制，公开部署前必须先收紧权限。actor 的完整机制（cookie 必须
非 HttpOnly、`actor_tenant` session 键等）见
[authx-foo 的 Admin 后台](authx-foo-admin.md)。

### 周边依赖（非 Ash 生态主体）

- `igniter` / `sourceror`：Ash、Phoenix 代码生成工具，仅在 dev/test 使用。
- `picosat_elixir`：Ash 策略引擎使用的 SAT 求解器。
- `db_ops`：发布环境中的轻量数据库操作（create / seed / drop），与认证无关。
- `reactor`、`spark`、`splode`：`ash` 的必需传递依赖（流程编排、DSL、错误结构）。

## 3. 一次登录中谁做了什么

```text
浏览器访问 /sign-in
  └─ ash_authentication_phoenix 渲染默认登录页（含 Authx 按钮）

点击“使用 Authx 登录” → GET /auth/user/authx
  └─ ash_authentication 的 OIDC 策略：读 discovery、生成 state/nonce/PKCE、302 到 Authx

Authx 授权完成 → GET /auth/user/authx/callback
  └─ ash_authentication_phoenix 的 auth_routes 接收回调
  └─ ash_authentication 校验 ID Token、换 token
  └─ ash 执行 register_with_authx 动作：写 users / user_identities / tokens
     （ash_postgres 落库）

重定向回首页
  └─ AuthController.success/4（ash_authentication_phoenix）→ store_in_session
  └─ 后续请求 load_from_session（ash_authentication）恢复 current_user
  └─ LiveView 由 ash_authentication_live_session 注入当前用户
```

## 4. 精简建议

- 想减小依赖树：移除 `ash_admin`（以及 `router.ex` 中的 `/admin` 作用域、
  `AshAdmin.Domain` 扩展）。`ash_phoenix` 仍会作为
  `ash_authentication_phoenix` 的传递依赖保留。
- 想移除 `ash_authentication_phoenix`：需要手写登录页、OAuth 回调控制器、
  会话读写与 LiveView 用户加载，相当于重做本项目最核心的部分，不建议。
- `ash`、`ash_postgres`、`ash_authentication` 是认证链路的必要组成，
  不可移除。
