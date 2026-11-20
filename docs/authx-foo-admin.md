# authx-foo 的 Admin 后台

> 对象：`_local/authx-foo`。AshAdmin 是本项目查看 / 修改 users、user_identities、
> tokens 数据的调试入口。
> 依赖分工见 [authx-foo 的 Ash 相关依赖](authx-foo-ash-libraries.md)，
> 登录流程见 [Authx Foo 接入 Authx OIDC](authx-foo-oidc-client.md)。

## 1. 入口与环境

- 顶部导航右上角的 **Admin** 链接（`components/layouts.ex`）指向 `/admin`。
- 路由在 `router.ex` 中**无条件挂载**，dev / test / prod 都可用：

  ```elixir
  pipeline :admin do
    plug :put_admin_actor
  end

  scope "/admin" do
    pipe_through [:browser, :admin]
    ash_admin "/", session: [{__MODULE__, :admin_session, []}]
  end
  ```

- 侧栏按 domain 自动列出资源；本项目只暴露 `AuthxFoo.Accounts` 下的
  `User`、`Token`、`UserIdentity`。

## 2. 以当前登录 User 为 actor

### 原理

AshAdmin 的 actor 不是由服务端直接读取的，链路是：

```text
浏览器 JS document.cookie
  → LiveView connect params（AshAdmin 的 liveSocket params()）
  → AshAdmin.ActorPlug.actor_assigns/2
  → 按 actor_resource / actor_domain / actor_primary_key 加载记录
```

因此服务端要做的只是：在渲染 `/admin` 的响应里写好这些 cookie。
`router.ex` 的 `:put_admin_actor` 在 `:browser` 之后运行，
`conn.assigns.current_user`（由 `load_from_session` 提供）存在时写入：

| cookie | 值 |
|---|---|
| `actor_resource` | `User` |
| `actor_domain` | `Accounts` |
| `actor_primary_key` | 当前用户 id |
| `actor_action` | `read` |
| `actor_authorizing` | 当前设为 `false`（绕过授权，侧栏显示 "Auth bypassed"）；设为 `true` 则按 policy 授权 |
| `actor_paused` | `false`，表示 actor 生效 |

未登录访问 `/admin` 时删除这些 cookie。

### 两个必须注意的点

1. **cookie 必须是 `http_only: false`。**
   `Plug.Conn.put_resp_cookie/4` 的 `:http_only` 默认是 `true`，一旦写成
   HttpOnly，`document.cookie` 读不到，connect params 里就没有 actor，
   页面会显示 "No actor"，且没有任何报错。当前统一使用：

   ```elixir
   defp admin_cookie_opts, do: [path: "/", http_only: false, same_site: "Lax"]
   ```

2. **session 里必须有 `"actor_tenant"` 键。**
   `AshAdmin.ActorPlug` 的匹配要求该键存在，但 AshAdmin 的 cookie 复制列表
   里没有 `actor_tenant`。`router.ex` 通过 `ash_admin` 的 `:session` 选项注入：

   ```elixir
   ash_admin "/", session: [{__MODULE__, :admin_session, []}]

   def admin_session(_conn), do: %{"actor_tenant" => nil}
   ```

   没有它时，连接后的页面正常，但首屏（disconnected render）actor 为 nil。

### 首屏时序

- **登录后第一次进入 `/admin`**：本次响应才写入 actor cookie，服务端渲染
  时还读不到，首屏侧栏可能短暂显示 "No actor"；WebSocket 连接后 JS 读到
  cookie 并作为 connect params 上报，actor 随即出现。
- **再次进入 `/admin`**：请求已带 cookie，首屏即显示
  `User: <uuid>` 与 "Auth enforced / Auth bypassed"。

## 3. 资源侧配置

`lib/authx_foo/accounts/user.ex`：

```elixir
use Ash.Resource,
  ...
  extensions: [AshAuthentication, AshAdmin.Resource]

admin do
  actor? true
end
```

- 必须加入 `AshAdmin.Resource` 扩展，`admin` 段才可用。
- `actor? true` 让 User 出现在侧栏的 actor 候选列表中，并允许按 id 加载。

## 4. 权限

演示项目为便于操作数据，`User` 与 `Token` 都保留了 AshAuthentication 的
bypass，并额外加了一条 allow-all policy：

```elixir
policy always() do
  authorize_if always()
end
```

当前项目把 `actor_authorizing` 设为 `false`，AshAdmin 以 `authorize?: false`
执行，直接绕过 policy（actor 仍会加载并显示）。即使改成 `true`，上面的
allow-all policy 也会让以 User 为 actor 的读写全部放行。

## 5. 验证

```sh
# 看 Set-Cookie 是否可被 JS 读取（不应出现 HttpOnly）
curl -s -D - -o /dev/null -H "Cookie: _authx_foo_key=<session>" \
  http://localhost:4002/admin | grep -i "set-cookie: actor"
```

浏览器侧：

- DevTools → Application → Cookies，确认 `actor_*` 存在且 **HttpOnly = false**；
- 侧栏 Actor 区应显示 `User: <本地用户 id>`，状态点为绿色；
- 打开 `Users` 页面能列出数据，说明 actor 加载与数据访问正常
  （当前 `actor_authorizing=false`，请求不经过 policy）。

## 6. 安全说明

`/admin` 当前**没有访问控制**，且资源 policy 整体放开，这是演示环境的刻意选择。
公开部署前至少应做到其中之一：

- 只在受信网络或本地开启 `/admin`（用环境变量或 `dev_routes` 控制路由）；
- 在 `:admin` pipeline 前加 `Plug.BasicAuth` 或要求 `current_user` 存在并跳转登录；
- 把资源上的 allow-all policy 换回按 actor / action 的实际授权规则。
