# 用户侧 OIDC 授权撤销（Consent Revocation）

> 状态：设计稿，代码尚未实现。本文先明确语义与数据模型，再给出首版实现步骤和后续优化路线。

## 结论摘要

首版做**用户自助撤销自己在 Authx 对某个客户端的 OIDC 授权**，交互模型参考
GitHub 的 *Authorized OAuth Apps* 页面：登录后看到「我已授权的应用」列表，
逐个撤销，撤销前确认，撤销后给出明确结果提示。

必须先定义清楚三个容易混淆的概念（GitHub/Google 的设置页也都在强调这个区分）：

- **退出某个应用**：只结束客户端应用自己的会话，Authx 无感知。
- **退出 Authx**：结束 Authx 的 SSO 浏览器会话，不删除 consent，也不影响客户端会话。
- **撤销授权（consent）**：删除「用户已同意某客户端使用某些 scope」的记录。
  之后该客户端再次发起授权时必须重新征求同意。它**不结束任何会话**，也
  **不会让已签发的 access token 立即失效**。

首版只做第三件事，且只由用户在 Authx 页面发起；不做客户端侧静默撤销，
不承诺即时吊销已签发令牌。后续按优先级补 RP-Initiated Logout、令牌吊销、
撤销通知等（见第 11 节）。

## 1. 现状盘点

### 1.1 当前协议端点

[`AuthxWeb.OidcController`](../lib/authx_web/controllers/oidc_controller.ex) 与
[`router.ex`](../lib/authx_web/router.ex) 目前只发布：

- `GET /oidc/authorize`、`POST /oidc/authorize`（consent 提交）
- `POST /oidc/token`
- `GET/POST /oidc/userinfo`
- `GET /oidc/jwks`、`GET /.well-known/openid-configuration`

没有 `end_session_endpoint`，没有 `revocation_endpoint`，也没有「已授权应用」
页面。`/sign-out` 由 `sign_out_route` 生成，只执行
`clear_session(:authx)`（[`AuthxWeb.AuthController.sign_out/2`](../lib/authx_web/controllers/auth_controller.ex)）。

### 1.2 Consent 资源

[`Authx.Oauth.Resources.Consent`](../lib/authx/oauth/resources/consent.ex) 按
`(user_id, client_id)` 唯一，保存合并后的 `scope` 和 `granted_at`：

- action：`defaults [:read, :destroy]`、`create :grant`（upsert）。
- policy：只有 `AshAuthentication.Checks.AshAuthenticationInteraction` bypass，
  没有面向用户或开发者的读/删策略。

### 1.3 库对 consent 的读取方式（关键约束）

`ash_authentication_oauth2_server` 的
`Authorize.consented?/5` 通过 `stored_scope/5` 做一次
`filter(user_id == ^user.id and client_id == ^client.id) |> Ash.read_one()`，
**不检查任何状态字段**：有行即视为已授权，且行内 scope 必须是请求 scope 的
超集。`grant_consent!/5` 在旧 scope 上合并后 upsert。

这意味着：**删除 consent 行是让 `consented?/5` 变为 false 的最直接方式**，
不需要改库；软删除则需要替换所有 consent 读取路径（见 2.2 的方案对比）。

### 1.4 令牌现状

- access token 是 AshAuthentication 签发的 JWT，默认有效期 1 小时
  （`access_token_lifetime` 未在 [`Authx.Oauth.Oidc.Server`](../lib/authx/oauth/oidc/server.ex) 覆盖）。
  `BearerPlug` 只验签，没有存储或吊销列表。
- ID Token 的 `exp` 为 5 分钟（[`oidc_controller.ex`](../lib/authx_web/controllers/oidc_controller.ex)）。
- 当前不签发 refresh token。
- authorization code 默认 10 分钟；**token 交换不检查 consent 是否仍存在**。

因此撤销 consent 的实际效果边界是：**影响下一次授权请求；不影响已发出的
令牌和已有会话**。这一点必须在 UI 上写清楚，否则用户会误以为撤销后所有
访问立刻中断。

## 2. 参考产品设计

### 2.1 GitHub：Settings → Applications

GitHub 把「谁在代表你做事」拆成三个独立列表，而不是混在登录设备/会话里：

- **Authorized OAuth Apps**：你授权过的 OAuth 应用及其 token。
- **Authorized GitHub Apps**：你以本人身份授权过的 GitHub App，撤销后
  相关 token 失效。
- **Installed GitHub Apps**：安装在账号/组织上的 App，控制的是安装范围
  （仓库访问等），与「代表你行事」是不同维度。

Authorized OAuth Apps 页面上的交互：

- 每个应用一行，展示应用身份与授权信息，行尾 kebab 菜单里有 **Revoke**。
- 页面提供 **Revoke all** 批量撤销。
- 撤销会立即使该应用持有的 OAuth token 失效；应用不会收到「用户已撤销」
  的通知，只会在之后调用 API 时失败。
- 撤销只停止未来访问，**不会删除应用已经拿到的数据**；这一点 GitHub 在
  相关文档中明确说明。
- 授权与登出、SSH key、PAT 是不同入口，互不等价。

Google 的 *Third-party apps with account access* 采用同样的模型：每个应用
显示可访问的数据范围、"last accessed"，操作为 *Remove access*。

### 2.2 可借鉴的设计

1. **术语分开**：页面标题用「已授权的应用」，操作叫「撤销授权」，不叫
   「退出登录」或「删除应用」。
2. **一应用一行**：应用名、授权范围（人类可读）、授权时间、最近活动、撤销
   入口。字段服务于同一个判断——「这个应用还值得信任吗」。
3. **逐应用撤销**，不做隐式批量；批量撤销（Revoke all）可以是后续增强。
4. **撤销前确认**，撤销后显示结果；不把撤销做成 hover 即触发。
5. **明确效果**：撤销后下次要重新同意；已经获得的访问在过渡期内可能仍有效，
   已导出的数据无法收回。
6. **可审计**：记录谁在何时撤销了哪个应用、哪些 scope。GitHub 的帮助文档
   也引导用户在安全日志中确认意外的授权。
7. **入口位置**：放在账号设置而非管理员后台；管理员不应默认拥有替用户
   撤销的能力。

### 2.3 不照搬的部分

- GitHub 的「OAuth App / GitHub App」双模型；Authx 只有一种 OIDC client，
  不需要两套授权概念。
- GitHub 能即时吊销 token，是因为其 token 服务端有状态。Authx 当前是
  无状态 JWT，**首版不能承诺同样的即时性**；这属于后续工作，不是 UI 文案
  可以掩盖的差异。
- GitHub App 的「安装范围」概念（repository access）；Authx 客户端没有
  资源范围模型。

## 3. 目标与非目标

### 目标（首版）

- 已登录用户在 Authx 查看自己有效授权的客户端列表。
- 看到每个客户端的授权 scope 摘要、授权时间、应用最近活动（可用的近似值）。
- 撤销单个客户端授权，带确认和结果提示。
- 撤销后，该客户端下一次授权请求必须重新显示 consent 页面。
- 撤销操作有归属校验和最小审计记录；用户只能撤销自己的 consent。

### 非目标（首版）

- 客户端发起的撤销端点、`end_session_endpoint`、`revocation_endpoint`。
- 已签发 access token / ID token 的即时失效。
- 按 scope 的细粒度撤销（先整客户端撤销）。
- 通知客户端「授权已被撤销」（back-channel logout / webhook）。
- 管理员替用户撤销、批量撤销。
- 撤销 Authx 登录会话或客户端本地会话。

## 4. 语义与效果矩阵

| 事件 | consent 行 | Authx SSO 会话 | 客户端本地会话 | 已签发 access token | 下一次 authorize |
|---|---|---|---|---|---|
| 用户在本页撤销授权 | 删除（+审计） | 保留 | 保留 | 有效至过期（≤1h） | 重新显示同意页 |
| 用户访问 `/sign-out` | 保留 | 结束 | 保留 | 有效至过期 | 需重新登录 Authx，但不重新同意 |
| 客户端自己登出 | 保留 | 保留 | 结束（客户端实现） | 有效至过期 | 视客户端实现 |
| 用户重新同意 | 重新创建 | 保留 | 保留 | 新签发 | 直接签发（有覆盖 scope 的 consent） |
| 撤销 developer 资格 | 保留 | 保留 | 保留 | 有效至过期 | 不受影响（consent 属于用户与客户端） |

说明：撤销 consent 后，撤销前已签发但尚未兑换的 authorization code 仍可
完成一次 token 交换（10 分钟内）。首版接受这个窗口；若要关闭，需在 token
交换时校验 consent（见 11.3）。

## 5. 数据模型设计

### 5.1 方案对比

| 方案 | 优点 | 缺点 |
|---|---|---|
| **A. 物理删除 consent 行 + 独立审计表（推荐）** | 与库语义完全一致；`consented?/5` 自动为 false；再次同意时 upsert 自然重建；无库耦合改动 | 需要新增审计资源；consent 表本身不保留历史 |
| B. consent 增加 `revoked_at` 软删除 | 历史集中在同一行 | 库读取不认该字段，必须包装 `consented?/5` 并保证所有读取路径都过滤；`:grant` upsert 必须清空 `revoked_at`；并发撤销/重新同意更易出错 |
| C. 只保留 `:destroy`，不记审计 | 改动最小 | 不满足可审计要求，无法回答「谁在何时撤销了什么」 |

选择 A。OAuth 里 consent 是「当前授权状态」，没有「已停用但保留」的协议
语义；历史应由审计数据承载，而不是混进状态行。注意这与「客户端停用」不同：
客户端记录不能物理删除，consent 的物理删除恰恰是撤销语义本身。

### 5.2 审计资源

新增 `Authx.Oauth.Resources.ConsentRevocation`：

```text
oauth_consent_revocations
  id            uuid_v7 pk
  user_id       uuid       # 撤销者（也是 consent 的属主）
  client_id     uuid
  client_name   text       # 快照，便于客户端改名/删除后审计仍可读
  scope         text       # 撤销时被移除的 scope 快照
  source        text       # "self_service"；未来可为 "admin" / "user_disabled"
  revoked_at    utc_datetime_usec
```

约定：

- 只允许 create/read，不允许 update/destroy（append-only）。
- 不记录 token、code、密码等敏感凭据。
- `client_name` 用快照而非 join，审计记录不随客户端改名而变化。
- 外键策略：审计数据要求长期可读，建议**不加级联删除**；若未来允许删除
  用户/客户端，应使用 `nilify` 或不做外键并保留快照。consent 表当前已有
  user/client 外键，删除仍受约束。

### 5.3 consent 表

首版不改表结构。`granted_at` 已经足够展示授权时间；无需 `updated_at`。

## 6. 领域 action 与策略

### 6.1 Consent 资源

增加显式的用户可调用 action，而不是让界面直接调用 `:destroy`：

```elixir
actions do
  defaults [:read, :destroy]

  create :grant do
    # 保持现状，供协议流程使用
  end
end
```

建议：

- 保留 `:destroy` 但通过策略限制为 consent 属主本人；或者在
  `Authx.Oauth.Consents` 中统一封装 `revoke/2`，内部用 `:destroy` +
  同事务写审计。首版二选一，不要两条路径并存。
- 读取必须带 `user_id` 归属条件；列表需要预加载 client：

```elixir
Consent
|> Ash.Query.filter(user_id == ^user.id)
|> Ash.Query.load(:client)
|> Ash.Query.sort(granted_at: :desc)
|> Ash.read!(actor: user)
```

- 策略（示意）：

```elixir
policies do
  bypass AshAuthentication.Checks.AshAuthenticationInteraction do
    authorize_if always()
  end

  policy action_type(:read) do
    authorize_if relates_to_actor_via(:user)
  end

  policy action(:destroy) do
    authorize_if relates_to_actor_via(:user)
  end
end
```

`relates_to_actor_via(:user)` 要求 actor 是 `%Authx.Accounts.User{}` 且与记录
`user_id` 一致。不要接受表单传入的 `user_id` 作为身份依据，actor 必须来自
已认证会话。

### 6.2 上下文 API

新增 `Authx.Oauth.Consents`（遵循项目的命名约定）：

```elixir
# 用户自己的授权列表；永远返回 list
def list_for_user(%User{} = user)

# 严格查找，供撤销使用；只在该用户范围内查
def fetch_for_user(%User{} = user, consent_id) ::
  {:ok, %Consent{}} | {:error, :not_found}

# 撤销：删除 consent + 写审计，同一事务
def revoke(%User{} = user, %Consent{} = consent) ::
  {:ok, %Consent{}} | {:error, term()}
```

实现要点：

- `fetch_for_user/2` 过滤 `user_id == actor.id`，避免越权 ID 探测；
  不存在的 consent 一律返回 `:not_found`。
- `revoke/2` 在一个 `Ash.transact` 中：删除 consent（actor 走策略）→
  创建 `ConsentRevocation`（快照 `client_name`、`scope`）。
- 并发：consent 删除和重新同意可能交错。删除影响 0 行时返回
  `{:error, :not_found}`，UI 提示后刷新列表；不要静默成功。
- 不把 `revoke/2` 放进 `Authx.Oauth.Clients`：consent 是用户对客户端的状态，
  不是开发者的客户端管理操作，权限主体也不同。

### 6.3 读取 client 的策略冲突

列表需要展示应用名，但 `Client` 的 read 策略目前只允许**属于该客户端的
developer** 读取（见 `Authx.Oauth.Resources.Client` 的策略）。普通用户作为
actor 直接 `Ash.Query.load(:client)` 时，关联读取同样受策略约束，会被拒绝
或返回空关联。

可选方案：

| 方案 | 说明 | 评价 |
|---|---|---|
| A. 通过 consent 关联授权读取 | 给 `Client` 增加 `has_many :consents`，策略增加 `action_type(:read)` 下 `authorize_if relates_to_actor_via([:consents, :user])` | 语义正确：用户只能读到「自己确实授权过」的客户端；但会顺带开放 client 的其他 public 字段，必要时为该场景定义专用 read action 并用 `select` 限制字段 |
| B. 领域层受控读取 | `list_for_user/1` 先按 actor 查出 consent（策略已保证归属），再批量按 id 取 client 的展示字段，使用受控的内部读取 | 实现简单；必须写清「先确认归属再关策略」的顺序，避免变成通用 `authorize?: false` 后门，并补越权测试 |
| C. 冗余快照 | 在 consent 上保存 `client_name` | 会随客户端改名过期，不适合作为主展示来源；审计表仍建议保留快照 |

首版建议 **A 或 B 择一**。若选 B，应把内部读取封装在 `Authx.Oauth.Consents`
内、只暴露 `client_name` 等展示字段，并在测试中证明普通用户无法借此读取
他人的客户端或其他字段。无论选哪种，都不要为了让页面渲染而全局放开
Client 的 read 策略。

## 7. 页面与交互设计

### 7.1 路由与访问

在 `ash_authentication_live_session` 的 authenticated scope 内新增：

```elixir
live "/settings/applications", Settings.ApplicationsLive, :index
```

LiveView 使用 `on_mount {AuthxWeb.LiveUserAuth, :live_user_required}`。未登录
用户被重定向到 `/sign-in`，登录后回到本页。页面属于账号设置，不属于
`/admin`，因此**不检查 admin**。

导航：在已登录布局的用户菜单中增加「已授权的应用」。这是普通用户入口，
不放在开发者的客户端管理入口下。

### 7.2 页面结构（参考 GitHub，不做照抄）

```text
┌──────────────────────────────────────────────────────────────┐
│ 账号设置 / 已授权的应用                                       │
│                                                              │
│ 这些应用可以使用 Authx 登录并访问你允许的信息。撤销后，        │
│ 应用需要重新获得你的授权。撤销不会退出你在这些应用中的登录。    │
│                                                              │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ Demo App                              [撤销授权]          │ │
│ │ 可访问：登录身份、邮箱                                    │ │
│ │ 授权时间：2026-11-18 10:24                                │ │
│ │ 应用最近活动: 2026-11-18 12:03（如可用）                  │ │
│ └──────────────────────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ Foo App                               [撤销授权]          │ │
│ │ 可访问：登录身份、邮箱、基本资料                          │ │
│ │ 授权时间：2026-11-16 09:12                                │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                              │
│ 没有更多应用。                                                │
└──────────────────────────────────────────────────────────────┘
```

字段决策：

| 字段 | 来源 | 说明 |
|---|---|---|
| 应用名 | `client.client_name` | 空值回退「未命名应用」；不展示 `client_id` 作为主标识 |
| 开发者/归属 | `client.developer` | 首版可不展示；后续可显示「由 X 开发」 |
| 授权范围 | `consent.scope` | 映射为人类可读文案（见 7.3） |
| 授权时间 | `consent.granted_at` | 重新同意会刷新该值 |
| 最近活动 | `client.last_used_at` | **注意：这是客户端维度的最近 token 交换时间，不是「该用户的最近使用」**，首版标签用「应用最近活动」；按用户粒度见 11.1 |
| 撤销 | consent id | 不传 user_id / client_id 作为授权依据 |

### 7.3 scope 文案

与 [`oidc-scopes.md`](oidc-scopes.md) 保持一致，UI 层做映射：

- `openid` → 登录身份
- `email` → 邮箱地址
- `profile` → 基本资料

未知 scope 原样显示（不允许未知 scope 发授权请求的逻辑仍在 `validate_request`）。
服务端按固定顺序展示，避免 unordered 文本。

### 7.4 交互流程

1. 用户点击「撤销授权」。
2. 展开行内确认或打开对话框，明确写出：
   - 应用将不能再自动登录；
   - 下次使用需要重新同意；
   - 已在应用中的登录不会被退出；
   - 已经签发的访问凭证在过期前可能仍然有效（最长约 1 小时）。
3. 确认后 `phx-click="revoke"` + `phx-value-id`，LiveView 用
   `current_user` 调 `Consents.fetch_for_user/2` 再 `revoke/2`。
4. 成功：`stream_delete` 移除该行，flash 提示「已撤销对 Demo App 的授权」。
5. 失败/已被撤销：提示并重新拉取列表（`stream(..., reset: true)`）。
6. 列表使用 LiveView stream，空状态用 `only:block` 文案，符合项目约定。

撤销按钮必须带唯一的 DOM id（如 `revoke-consent-<id>`），确认按钮同理，
便于测试。

### 7.5 可访问性与细节

- 撤销是破坏性但可恢复的操作：使用中性按钮样式 + 明确确认，不使用
  「删除」字样，避免用户误以为会删除应用或数据。
- 确认默认焦点落在「取消」，避免误触。
- 空状态与加载状态给出清晰说明。
- 页面顶部固定说明「撤销 ≠ 退出登录」，减少支持成本。

## 8. 安全与威胁模型

| 风险 | 对策 |
|---|---|
| 越权撤销他人 consent（IDOR） | actor 来自会话；查询与删除都带 `user_id == actor.id`；越权一律 `:not_found` |
| CSRF | LiveView 事件走 websocket + session；若改用普通表单，必须保留 `protect_from_forgery` |
| 客户端伪造撤销 | 首版不提供客户端撤销入口；未来若提供，必须要求用户在场（浏览器跳转 + 确认），不能仅凭 `client_id`（公开客户端无法保密） |
| 误操作 | 二次确认 + 结果提示；不提供 hover 触发 |
| 撤销竞态 | 删除影响 0 行返回 `:not_found`；列表刷新；审计只在事务内随删除成功写入 |
| 审计污染 | 审计写入不接受用户输入的身份字段；`source` 由服务端设定；不记录 token/code |
| 枚举 | 页面只展示当前用户的 consent；不提供按 client_id 的公开查询 |
| 撤销后旧令牌 | UI 明示最长约 1 小时窗口；即时失效列入后续工作，不虚假承诺 |
| 管理员越权 | 管理员不因角色自动获得替用户撤销的能力；如未来提供，须独立入口与审计 |

补充：consent 的 `destroy` 不应暴露给协议 internals 之外的任意 actor。
Ash Admin 也暂不暴露该资源，避免运营界面绕过用户同意语义。

## 9. 测试计划

单元/策略测试（`test/authx/oauth/consents_test.exs`）：

- 用户可以列出自己的 consents，且包含 client 信息。
- 用户看不到、也无法撤销他人的 consent（返回 `:not_found`）。
- 匿名 actor 被拒绝。
- developer 与 admin 不能顺带获得普通用户的 consent 管理权限。
- `revoke/2` 删除 consent 并在同一事务写入审计；审计包含正确快照。
- 重复撤销：第二次返回 `:not_found`，审计不重复写入。

协议回归（`test/authx_web/controllers/oidc_controller_test.exs`）：

- 用户同意 → 撤销 → 再次 authorize 渲染 consent 页面，而不是直接发 code。
- 撤销后重新同意 → consent 重建，后续 authorize 直接发 code。
- 撤销不影响其他用户或同一用户对其他客户端的 consent。
- 撤销期间已发出的 code 在有效期内仍可兑换（明确记录该行为，避免误判回归）。

LiveView 测试（`test/authx_web/live/settings/applications_live_test.exs`）：

- 未登录访问重定向到 `/sign-in`。
- 列表渲染应用名、scope 文案、授权时间；空状态正确。
- 点击撤销 → 出现确认 → 确认后行消失、出现成功提示。
- 直接构造他人 consent 的 id 无法撤销。

迁移测试：新表可回滚，索引与外键符合预期。

## 10. 实施步骤

1. **数据层**：新增 `ConsentRevocation` 资源与迁移；补 consent 面向用户的
   read/destroy 策略。
2. **领域层**：新增 `Authx.Oauth.Consents`（`list_for_user/1`、
   `fetch_for_user/2`、`revoke/2`），审计写入与删除同事务；补测试。
3. **界面**：`Settings.ApplicationsLive` + 路由 + 已登录导航入口；
   列表使用 stream，撤销带确认；补 LiveView 测试。
4. **文档**：把 [`oidc-client-management.md`](oidc-client-management.md)
   中「退出应用只结束应用会话，不等于撤销 consent」一段更新为「当前已支持
   用户自助撤销」，并链接本文；在 `_overview.md` 增加入口。
5. **验收**：按第 9 节跑完；`mix precommit` 通过。

建议一次 PR 完成 1–2，另一次 PR 完成 3 与文档；两者可独立回滚。

## 11. 后续优化路线

按优先级排列，均为独立可交付项。

### 11.1 用户粒度的「最近使用」与更好的列表信息

当前 `oauth_clients.last_used_at` 是客户端维度（token 交换时由库更新），
只能说明「这个应用最近被任何人用过」。若要在列表中显示「你最近使用」：

- 在 consent 行增加 `last_used_at`，在 authorize 签发 code 或 userinfo 时
  按 `(user_id, client_id)` 更新；为避免每请求写库，可节流（例如同一
  consent 每小时最多更新一次）或异步写入。
- 增加「最近使用」排序，帮助用户识别陈旧授权。

### 11.2 批量撤销与「撤销全部」

数据模型无需变化：按用户遍历 consent 删除，每条写入审计，或增加一条
batch 审计记录。注意与 GitHub 相同的坑：批量撤销不应意外影响非 OAuth
概念（Authx 中即登录会话）。首版用户可能只有少量应用，优先级低于 11.3。

### 11.3 撤销对未来令牌的强制生效

当前撤销后仍存在两个窗口：已发出的 authorization code（≤10 分钟）可在
撤销后兑换；已签发的 access token 在过期前仍有效。改进顺序：

1. **token 交换时校验 consent**：在 `POST /oidc/token` 成功后、签发令牌前
   查询该用户对该 client 的 consent 是否仍覆盖 code 的 scope；不覆盖则
   `invalid_grant`。成本是一次索引查询，语义清晰，建议优先做。
2. **userinfo / 资源访问时校验 consent**：让 `userinfo` 在验签之外检查
   consent 仍存在。会增加每请求 DB 读取，需评估；也可结合短期 access
   token 降低影响。
3. **真正的即时吊销**：引入 `jti` 拒绝列表、opaque token + introspection，
   或缩短 access token 寿命并依赖刷新。属于令牌模型变更，单独设计。

### 11.4 RP-Initiated Logout

新增 `end_session_endpoint` 并发布到 discovery：

- 校验 `id_token_hint` 的签名、issuer、audience 和时效；
- `post_logout_redirect_uri` 必须匹配客户端注册的回调/登出白名单；
- 结束 Authx SSO 会话后跳转，并说明「已退出 Authx，但未撤销应用授权」。

它与 consent 撤销是两个动作，页面和文案必须分开。客户端登出时可选调用，
不能默认等同于撤销授权。

### 11.5 撤销通知客户端（Back-Channel Logout / 撤销事件）

OIDC Back-Channel Logout 可以在用户撤销或会话结束时，由 Authx 向客户端
后端发送 logout token。需要：

- 客户端注册 `backchannel_logout_uri`，并校验 logout token 的签名与事件；
- 与 consent 撤销解耦：撤销授权不等于结束客户端会话，是否同时通知需要
  产品决策；
- 失败重试、超时和审计。

当前客户端模型没有该字段，可先作为配置扩展，默认关闭。

### 11.6 细粒度 scope 撤销

允许用户保留「登录身份」但移除「邮箱」授权：

- 库的 consent 语义是「行内 scope 是请求 scope 的超集」，因此实现方式是
  删除后按剩余 scope 重建 consent（会重置 `granted_at`），或改造为
  per-scope 行；
- 需要处理客户端下次只请求被撤销 scope 时的同意交互；
- 审计记录应保存被移除的具体 scope；
- UI 上要做 scope 级勾选与确认，复杂度明显高于整客户端撤销，放在后面。

### 11.7 管理员应急与账号禁用联动

- 管理员「替用户撤销」需要独立权限、明确审计和确认，不能复用用户的
  self-service 路径，也不能让 admin 角色默认获得该能力（与客户端归属模型
  一致）。
- 用户被禁用/删除时，应批量撤销其 consent，并定义已签发令牌与
  authorization code 的处理方式。当前系统尚未实现用户禁用语义，需与
  [生产化计划](oidc-production.md) 中的门禁一起设计。

### 11.8 审计展示与合规

- 面向用户展示「最近的授权活动」；面向管理员展示撤销审计。
- 长期可考虑引入 AshPaperTrail 或统一审计资源，但不要因此把敏感凭据写入
  审计记录。
- 明确审计保留期和用户删除账号后的处理方式（快照字段可保留，主体标识
  需匿名化或按政策删除）。

## 12. 待确认的产品决策

1. 撤销后是否立即在 token 交换时校验 consent（建议是，见 11.3）。
2. 是否在首版就展示「应用最近活动」；若展示，必须使用「应用维度」措辞。
3. 撤销是否要向客户端发送通知（首版建议否，见 11.5）。
4. 是否允许管理员替用户撤销，以及授权与审计流程。
5. 是否需要 scope 级撤销进入首版（建议否）。
6. consent 被撤销后重新同意，`granted_at` 是否要保留首次授权时间供展示
   （当前 upsert 会刷新；如需要，增加 `first_granted_at`）。

## 参考

- GitHub Docs — *Reviewing your authorized OAuth apps*：
  https://docs.github.com/en/apps/oauth-apps/using-oauth-apps/reviewing-your-authorized-oauth-apps
- GitHub Docs — *Reviewing and modifying installed GitHub Apps*（安装范围与
  「代表你行事」的区分）：
  https://docs.github.com/en/apps/using-github-apps/reviewing-and-modifying-installed-github-apps
- Google Account Help — *Third-party apps & services with account access*。
- RFC 7009 — OAuth 2.0 Token Revocation（后续令牌吊销端点的基础）。
- OpenID Connect RP-Initiated Logout 1.0。
- OpenID Connect Back-Channel Logout 1.0。
