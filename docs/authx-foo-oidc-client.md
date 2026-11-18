# Authx Foo 接入 Authx OIDC —— 实施方案

> 状态：**已审核并实施**。实现与本文档一致；后续变更请同步更新本文件。
> 参考实现：`_local/authx-demo`（见 [OIDC client demo](client-demo.md)）。

## 1. 目标与范围

让本地项目 `_local/authx-foo` 以 OIDC 客户端身份接入 Authx：

- 使用 Authorization Code + S256 PKCE。
- 公开客户端（`token_endpoint_auth_method=none`），不保存 client secret。
- 验证 ID Token 的签名、issuer、audience、时效与 nonce。
- 按 Authx 的 `sub` 关联本地用户，登录后在 foo 首页显示身份并支持退出 foo 会话。

不做的事：

- 不实现 refresh token、全局注销、动态客户端注册。
- 不把 foo 的会话或数据库与 Authx 合并。
- 不为 foo 复制 demo 的“同 email 不同 issuer”多身份模型；foo 只接入 Authx
  一个 issuer，使用 AshAuthentication 标准的 UserIdentity 资源保存 `sub`。

## 2. 与 demo 的差异（为什么不能照抄）

| 项目 | `_local/authx-demo` | `_local/authx-foo` |
|---|---|---|
| `ash_authentication` | 5.0.0-rc.17 | **4.15.1** |
| `ash_authentication_phoenix` | 3.0.0-rc.12 | **2.17.4** |
| OIDC 已接入 | 是 | 否 |
| 用户模型 | users 表直接存 `issuer` / `subject` / `email` | 只有 `id`，需要新增身份字段与资源 |

demo 在 v5 中可以用 `warn_on_missing_identity_resource?(false)` 关闭
“未配置身份资源”的警告；foo 所在 v4.15 没有该选项，且未配置
`identity_resource` 会触发编译期警告，并在未来的 5.x 中变成硬性要求。
因此 foo 采用框架标准的 **UserIdentity 资源**方案，而不是 demo 的
`users.issuer + users.subject` 直存方案。

结论：**不升级 foo 的 AshAuthentication 版本**，用 4.15 自带的 OIDC strategy
与 UserIdentity 扩展实现，减少对 foo 现有登录脚手架的破坏。

## 3. 总体流程

```text
浏览器 localhost:4002
   │  GET /auth/user/authx
   ▼
Foo (AshAuthentication OIDC strategy)
   │  读 discovery，生成 state/nonce/PKCE，302
   ▼
Authx localhost:4000 /oidc/authorize
   │  用户登录 + consent
   ▼
Foo /auth/user/authx/callback   ← code + state
   │  服务端 POST /oidc/token（client_id + code_verifier）
   ▼
验证 ID Token → 按 (strategy, sub) 查 UserIdentity
   │  无身份记录时按 verified email 匹配/创建本地用户
   ▼
写 UserIdentity + foo session → 重定向 /
```

## 4. 端口与客户端注册

Authx 开发服务器固定占用 `4000`（issuer `http://localhost:4000`）。
foo 当前默认端口也是 `4000`，必须错开：

- foo 本地默认端口改为 **4002**（测试配置已使用 4002，但测试不启动服务器）。
- foo 的 LiveDebugger 开发端口改为 **4008**；Authx 本地开发默认占用 4007，
  两个应用同时运行时才不冲突。
- foo 回调基址：`http://localhost:4002/auth`。
- 实际回调：`http://localhost:4002/auth/user/authx/callback`。
- 新增一个独立的 Authx 客户端，不复用 demo 客户端：

| 字段 | 值 |
|---|---|
| client_id | `00000000-0000-7000-8000-000000000002` |
| client_name | `Authx Foo local OIDC client` |
| redirect_uri | `http://localhost:4002/auth/user/authx/callback` |
| scope | `openid email` |
| token_endpoint_auth_method | `none` |
| grant_types / response_types | `authorization_code` / `code` |

`Client.register` 要求 actor 为 developer，因此仍由 `mix dev.seed` 以开发
管理员（同时是 developer）身份注册。同一 developer 可以拥有多个客户端。

## 5. 实施步骤

### 阶段 A：Authx 仓库（客户端注册）

#### A1. `config/dev.exs`

在现有 `demo_client_app` 旁增加：

```elixir
foo_client_app: %{
  client_id: "00000000-0000-7000-8000-000000000002",
  client_name: "Authx Foo local OIDC client",
  redirect_uri: "http://localhost:4002/auth/user/authx/callback",
  callback_env: "AUTHX_FOO_CALLBACK"
},
```

demo 配置保持兼容；`callback_env` 缺省时仍使用 `AUTHX_DEMO_CALLBACK`。

#### A2. `lib/mix/tasks/dev.seed.ex`

把“只注册 demo 客户端”的逻辑泛化为“注册所有已配置的本地客户端”：

- 新增 `client_configs/0`：依次读取 `:demo_client_app`、`:foo_client_app`，
  未配置则跳过。
- `ensure_demo_client!/1` → `ensure_client!/2`，按配置逐个执行现有的
  “加载 → 不存在则注册 → 存在则校验”流程。
- `ensure_no_legacy_demo_client!/1` 改为按各自 `client_name` 检查同名旧客户端。
- 回调覆盖变量从固定 `AUTHX_DEMO_CALLBACK` 改为
  `Map.get(config, :callback_env, "AUTHX_DEMO_CALLBACK")`。
- 输出信息同时列出两个 client id。
- 更新 `@moduledoc`。

不删除、不重命名 `:demo_client_app`，避免破坏现有配置与测试。

#### A3. `test/mix/tasks/dev_seed_test.exs`

- `setup` 中保存/恢复并设置 `:foo_client_app`。
- 新增测试：`mix dev.seed` 后两个固定 id 的客户端都存在，且
  `redirect_uris`、`scope`、`token_endpoint_auth_method` 符合预期。
- 现有“重复执行可重复”测试保持通过。

#### A4. 文档

- 本文件保留为 foo 接入说明。
- `docs/_overview.md` 增加一行链接。
- `docs/oidc-client-management.md` 的“当前本地开发使用”补充：
  `mix dev.seed` 现在同时注册 demo 与 foo 两个本地客户端。

### 阶段 B：`_local/authx-foo`

#### B1. `config/runtime.exs`

```elixir
# foo 本地默认端口 4002，避免与 Authx(4000) 冲突
config :authx_foo, AuthxFooWeb.Endpoint,
  http: [
    port:
      String.to_integer(
        System.get_env("PORT", if(config_env() == :dev, do: "4002", else: "4000"))
      )
  ]

config :authx_foo,
  oidc_client_id:
    System.get_env("AUTHX_CLIENT_ID", "00000000-0000-7000-8000-000000000002"),
  oidc_issuer: System.get_env("AUTHX_ISSUER", "http://localhost:4000"),
  oidc_redirect_uri: System.get_env("AUTHX_REDIRECT_URI", "http://localhost:4002/auth")
```

说明：demo 使用相同的 `AUTHX_CLIENT_ID` / `AUTHX_ISSUER` /
`AUTHX_REDIRECT_URI` 变量名，但两个应用不会同时在同一终端启动；如需同时
运行，分别在各自终端覆盖为不同端口/回调即可。生产环境应显式设置这三个
变量，不依赖 localhost 默认值。

#### B2. `lib/authx_foo/secrets.ex`

新增：

```elixir
def secret_for(
      [:authentication, :strategies, :authx, key],
      AuthxFoo.Accounts.User,
      _opts,
      _context
    )
    when key in [:client_id, :base_url, :redirect_uri] do
  config_key =
    case key do
      :client_id -> :oidc_client_id
      :base_url -> :oidc_issuer
      :redirect_uri -> :oidc_redirect_uri
    end

  Application.fetch_env(:authx_foo, config_key)
end
```

#### B3. `lib/authx_foo/accounts/user.ex`

1. `attributes` 增加：

```elixir
attribute :email, :ci_string do
  allow_nil? false
  public? true
end
```

2. `identities` 增加：

```elixir
identity :unique_email, [:email]
```

3. `actions` 中删除当前未使用且引用不存在字段的 `read :get_by_subject`
   （它按 `subject` 过滤，但 User 没有该属性；OIDC 使用 `register_with_authx`
   注册流程，不依赖此 action）。

4. 新增注册 action。v4.15 的 `IdentityChange` 不会把 `user_info` 写进用户属性，
   因此还需要一个小 change 在它之前把 email 落到用户记录上：

```elixir
# lib/authx_foo/accounts/changes/set_email_from_user_info.ex
defmodule AuthxFoo.Accounts.Changes.SetEmailFromUserInfo do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    user_info = Ash.Changeset.get_argument(changeset, :user_info)
    Ash.Changeset.change_attribute(changeset, :email, user_info["email"])
  end
end
```

```elixir
create :register_with_authx do
  argument :user_info, :map, allow_nil?: false
  argument :oauth_tokens, :map, allow_nil?: false, sensitive?: true

  upsert? true
  upsert_identity :unique_email
  upsert_fields [:email]

  change AshAuthentication.GenerateTokenChange
  change AuthxFoo.Accounts.Changes.SetEmailFromUserInfo
  change AshAuthentication.Strategy.OAuth2.IdentityChange
end
```

5. `authentication.strategies` 增加：

```elixir
oidc :authx do
  client_id AuthxFoo.Secrets
  base_url AuthxFoo.Secrets
  redirect_uri AuthxFoo.Secrets
  identity_resource AuthxFoo.Accounts.UserIdentity

  client_authentication_method "none"
  code_verifier true
  nonce true
  trust_email_verified? true
  authorization_params scope: "email"
end
```

要点：

- `openid` 由 Assent 自动加入 scope；客户端白名单为 `openid email`。
- `trust_email_verified? true`：Authx 签发 `email_verified`，且注册 action 用
  `unique_email` 作为 upsert identity，满足框架“按已验证 email 关联已有账号”
  的安全条件。
- 参数 `oauth_tokens` 必须 `sensitive?: true`，否则触发编译警告。
- 同一账号已有另一个 Authx `sub` 时，框架会拒绝自动关联，符合预期。

#### B4. 新增 `lib/authx_foo/accounts/user_identity.ex`

```elixir
defmodule AuthxFoo.Accounts.UserIdentity do
  use Ash.Resource,
    otp_app: :authx_foo,
    domain: AuthxFoo.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.UserIdentity]

  user_identity do
    user_resource AuthxFoo.Accounts.User
  end

  postgres do
    table "user_identities"
    repo AuthxFoo.Repo
  end
end
```

并在 `AuthxFoo.Accounts` 的 `resources` 中登记。

该扩展自动生成：

- `uid`（Authx `sub`）、`strategy`（`authx`）、`user_id`、access/refresh token 字段。
- `(uid, strategy)` 唯一身份。
- `upsert` / `read` / `destroy` action，以及与 User 的 belongs-to 关系。
- User 侧自动生成 `has_many :identities`（由 strategy 的 `identity_resource`
  触发，无需手写关系）。

#### B5. 数据库迁移

执行：

```sh
cd _local/authx-foo
mix ash.codegen add_authx_oidc_identity
mix ecto.migrate
```

预期迁移内容：

- `users.email`（`:citext`，非空）+ `users_unique_email_index` 唯一索引。
- `user_identities` 表：`id`、`user_id` FK、`uid`、`strategy`、token 字段、
  时间戳；`(uid, strategy)` 唯一索引。

注意：若 foo 开发库已有用户行，新增非空 `email` 会失败。本方案假定 foo
是本地试验库；如确有数据，执行前需先清空或人工回填。迁移文件生成后纳入
foo 仓库，不手写 SQL。

#### B6. 首页与控制器

`lib/authx_foo_web/controllers/page_controller.ex`：

```elixir
def home(conn, _params) do
  render(conn, :home, current_user: conn.assigns[:current_user])
end
```

`home.html.heex` 改为演示用的简洁页面（保留 `<Layouts.app flash={@flash}>`）：

- 未登录：说明文字 + `<a id="authx-sign-in" href="/auth/user/authx">使用 Authx 登录</a>`。
- 已登录：显示 `current_user.email`、本地用户 id，以及
  `<form action={~p"/sign-out"} method="delete">` 退出按钮。框架的
  `sign_out_route` 只生成 `DELETE /sign-out`（以及 GET 确认页），不能用 POST。
- 使用自定义 Tailwind 类做卡片式布局，不引入新依赖、不使用内联 `<script>`。

`auth_routes AuthController, AuthxFoo.Accounts.User, path: "/auth"` 已存在，
无需新增路由；OIDC 回调路径由框架生成：
`/auth/user/authx`、`/auth/user/authx/callback`。

#### B7. 测试

- `test/authx_foo_web/controllers/page_controller_test.exs`：
  - 未登录时 `#authx-sign-in` 的 `href` 为 `/auth/user/authx`。
- 新增 `test/authx_foo/accounts/authx_identity_test.exs`，直接调用
  `:register_with_authx`：
  - 同一 `sub` 重复注册得到同一本地用户；已关联后 provider 传来的新 email
    不会覆盖本地 email（框架的防篡改行为）。
  - 不同 `sub`、相同 email 时拒绝自动关联，用户仍只有一条本地记录。
  - 生成 UserIdentity 记录，`strategy == "authx"`，`uid == sub`。
- 不写依赖真实 Authx 网络的单元测试；完整 OIDC 往返在手工验收中覆盖。

## 6. 验收

### 自动

```sh
# 根仓库
mix precommit

# foo
cd _local/authx-foo && mix precommit
```

### 手工端到端

1. 根仓库准备开发库与两个客户端：

   ```sh
   mix dev.setup   # 或已有库时 mix dev.seed
   ```

   确认输出包含两个 `AUTHX_CLIENT_ID`。

2. 启动 Authx：

   ```sh
   mix phx.server   # http://localhost:4000
   ```

3. 启动 foo：

   ```sh
   cd _local/authx-foo
   mix phx.server                          # 默认 http://localhost:4002
   ```

4. 打开 `http://localhost:4002`，点击“使用 Authx 登录”：
   - 跳转 Authx，使用 `admin@l.h` / `password123456` 登录。
   - consent 页面批准 `openid email`。
   - 回到 foo，首页显示 Authx 账号的 email。
5. 退出 foo 后重新登录：
   - 不要求重新输入 Authx 凭据（Authx 会话仍有效时），仍得到同一个本地用户。
6. 在 Authx 侧撤销/删除该用户后再次登录，foo 应创建新的本地用户（旧身份成为
   孤立记录，可按需后续清理）。

## 7. 安全与限制

- foo 是公开客户端，只依赖 PKCE + state + nonce；不要在 foo 保存 Authx 密码或
  client secret。公开客户端的威胁模型、`client_id` 是否可被他人使用，以及
  后续增加 `client_secret_basic` / `private_key_jwt` / mTLS 的建议见
  [OIDC 客户端认证与公开客户端威胁模型](oidc-client-authentication.md)。
- foo 的 `(uid, strategy)` 身份记录只对应一个 issuer；若未来接入第二个 issuer，
  需改为按 issuer 区分或使用独立用户身份资源。
- 本地默认 issuer 是 `http://localhost:4000`，生产必须使用 HTTPS 并显式配置
  `AUTHX_CLIENT_ID`、`AUTHX_ISSUER`、`AUTHX_REDIRECT_URI`。
- Authx 端仍受预注册客户端限制，生产启用门禁见
  [OIDC 生产化与上线计划](oidc-production.md)。

## 8. 回滚

- foo：回退上述文件与迁移（`mix ecto.rollback`），删除 `user_identities` 与
  `users.email`；不改动现有 tokens 表。
- Authx：移除 `foo_client_app` 配置并恢复 `dev.seed` 单客户端逻辑；已注册的
  foo 客户端可在开发库手工删除，不影响 demo 与 Authx 登录。
