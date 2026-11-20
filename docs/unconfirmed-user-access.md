# 未确认用户访问方案

## 1. 背景

Authx 使用 Ash Authentication 的 confirmation add-on，并在密码策略中启用了：

```elixir
require_confirmed_with :confirmed_at
```

当用户密码正确但 `confirmed_at` 为空时，Ash Authentication 会拒绝登录，不会建立正常的认证 session。错误不一定都会到达 `AuthxWeb.AuthController.failure/3`：当前项目的认证页面是 LiveView，表单可能在 LiveView 内部直接消费错误并重新渲染表单。

参考：[Ash Authentication Confirmation Tutorial - Blocking unconfirmed users from logging in](https://ash-authentication.hexdocs.pm/confirmation.html#blocking-unconfirmed-users-from-logging-in)

## 2. 目标

未确认用户应能够访问一个受限的专属页面 `/auth/please-confirm`，用于：

- 说明账户尚未完成邮箱确认；
- 提供重新发送确认邮件的入口；
- 返回登录页面；
- 不获得应用内正常业务访问权限。

同时需要避免泄露邮箱是否已注册，并限制确认邮件重发接口被滥用。

## 3. 当前认证时序

```text
登录表单
  -> AshAuthentication 密码策略
  -> 校验密码
  -> 检查 confirmed_at
       |-- 已确认：创建认证状态，进入应用
       |-- 未确认：返回 UnconfirmedUser，不创建正常登录 session
```

因此，未确认用户不能依赖 `current_scope` 或 `current_user` 访问专属页面。控制器 failure callback 只覆盖经过 Phoenix controller 认证路由的失败；LiveView 表单提交则需要在表单/LiveView 错误处理处单独识别 `UnconfirmedUser`。

## 3.1 当前版本中的两个实际入口

项目当前锁定 `ash_authentication 5.0.0-rc.18` 和 `ash_authentication_phoenix 3.0.0-rc.12`。从依赖实现看，`require_confirmed_with` 会同时影响注册和密码登录，但错误传播路径不同：

- 注册：账户需要先创建出来，才能接收确认邮件。因此注册 action 在 transaction 完成后发现未确认，会返回 `AuthenticationFailed`，其 `caused_by` 是 `UnconfirmedUser`，但账户本身已经创建。注册 LiveView 会把它作为表单错误处理。
- 普通密码登录：当前页面使用 AshAuthentication Phoenix 的 LiveView sign-in form。启用 sign-in token 时，表单在 LiveView 内调用 `Form.submit/2` 读取用户；失败会留在 LiveView 内并重新渲染表单，不经过 `AuthController.failure/3`。只有后续浏览器请求确实进入 controller 认证路由时，才会触发 controller failure callback。

所以“注册时能看到 `UnconfirmedUser`，登录时看不到 controller log”是符合当前实现的，不能据此判断登录没有执行确认检查。应分别在注册 LiveView 和登录 LiveView 的表单错误对象中检查错误链。

## 4. 当前实现状态

第 4 步已完成初版，当前实现选择普通 controller POST 作为密码登录入口：

- `/sign-in` 使用 controller 页面，密码表单直接 POST 到 Ash Authentication controller route；
- `AuthController.failure/3` 识别 `UnconfirmedUser`，创建 pending session 并跳转 `/auth/please-confirm`；
- `/auth/please-confirm` 只接受有效 pending session；无效时清理状态并回到 `/sign-in`；
- pending session 保存 `user_id`、邮箱和创建时间；重发时仍以服务端读取的 `user_id` 为准；
- 确认页展示完整邮箱，并提供重新发送确认邮件入口；
- 登录页保留密码重置和 Magic Link 入口；
- 当前未实现限速、审计、API bearer 门禁和 OAuth/OIDC 未确认 actor 门禁；
- `/register` 已改为普通 controller POST，与登录使用同一套 `UnconfirmedUser` 分流，因此注册成功创建未确认账户后直接进入确认页。

当前页面和认证路由测试已覆盖基础结构；完整的未确认用户行为测试仍是后续最小步骤的一部分。

## 5. 方案对比

### 方案 A：继续禁止登录，在失败回调中进入专属页面（推荐）

保留 `require_confirmed_with :confirmed_at`，在 `AuthController.failure/3` 中单独处理未确认错误：

```text
登录失败：UnconfirmedUser
  -> 保存短期 pending confirmation 信息
  -> 跳转 /auth/please-confirm
  -> 用户点击重新发送
  -> 校验 pending 信息并发送确认邮件
```

用户始终没有正常认证身份，专属页面是公开页面，但只能提供“确认账户”相关操作。

待确认信息可以放在短期 session 中，最小化保存邮箱或用户 ID；也可以使用有签名、短期、一次性的 pending token。当前项目优先考虑 session 方案，后续若需要跨设备或更复杂的流程，再升级为 token 方案。

优点：

- 未确认用户不会进入应用业务区域；
- 权限边界清晰，漏拦截风险较小；
- 与当前 `require_confirmed_with` 配置一致；
- 改动集中在认证失败处理、专属页面和重发逻辑。

缺点：

- 登录失败后没有 `current_user` 可用；
- 需要安全地传递待确认邮箱或用户标识；
- 需要额外处理 session 过期、重复提交和重发限流。

### 方案 B：允许登录，再用全局访问门禁限制未确认用户

移除 `require_confirmed_with :confirmed_at`，让未确认用户建立 session，然后在 router plug 或 LiveView `on_mount` 中检查 `confirmed_at`：

```text
登录成功
  -> 取得 current_scope
  -> 未确认：只允许 /auth/please-confirm
  -> 已确认：正常访问应用
```

优点：

- 页面天然可以使用 `current_scope` / `current_user`；
- 重发确认邮件不需要传递邮箱；
- LiveView 流程较直观。

缺点：

- 必须确保所有页面、Plug、API、OAuth consent 和写操作都被门禁覆盖；
- 漏掉一个入口就可能让未确认用户读取或修改业务数据；
- 与“未确认用户禁止登录”的安全语义不同；
- 需要明确哪些低风险功能允许在未确认状态下使用。

该方案适合产品明确需要“已注册但未确认用户可以进入部分应用”的场景。若采用，不能只保护首页或 LiveView 页面，还必须审查所有可用路由和业务 action。

## 6. 推荐设计

采用方案 A：保持禁止登录，并新增公开的 `/auth/please-confirm` 确认等待页面。

建议路由：

```text
GET  /auth/please-confirm
POST /auth/please-confirm/resend
```

建议流程：

1. 在登录 LiveView 表单错误或 controller failure callback 中匹配 `AshAuthentication.Errors.UnconfirmedUser`。
2. 只有在服务端已经确认“该邮箱对应的密码验证成功，但账户未确认”后，才写入短期 pending session；绝不保存密码，也不让客户端重新提交任意邮箱。
3. 跳转到 `/auth/please-confirm`。
4. 页面展示确认说明和重发按钮。
5. 重发 action 只处理尚未确认的账户，并调用现有 confirmation sender。
6. 重发接口不接收任意邮箱参数，而是从 pending session 读取邮箱或用户 ID；若未来提供独立的按邮箱重发入口，再对所有情况返回统一的模糊提示。
7. 邮件发送成功后保留页面状态，不自动登录。
8. 用户点击确认链接完成确认后，回到登录页重新登录。

确认成功后建议重新登录，而不是让确认链接直接建立登录状态。这样确认动作和登录动作边界明确，也不会把确认 URL 当作长期登录凭证。

## 7. 安全风险与控制措施

### 7.1 邮箱枚举

风险：如果重发接口允许未登录用户提交任意邮箱，并根据邮箱返回“用户不存在”“已确认”等不同结果，攻击者可以批量探测注册邮箱。

控制：推荐的 pending session 方案不接受客户端提交邮箱，而是绑定到刚才已验证密码的账户。如果未来改成公开的按邮箱重发接口，则所有情况必须返回相同的模糊提示，例如：

> 如果该邮箱对应一个尚未确认的账户，我们已经发送了新的确认邮件。

页面和日志也不应将账户是否存在暴露给客户端。

### 7.2 重发邮件滥用

风险：攻击者反复触发重发，造成邮件骚扰、供应商费用或服务降级。

控制：

- 按邮箱和 IP 做频率限制；
- 设置最小发送间隔；
- 对短时间内重复请求统一返回，不重复发信；
- 记录审计事件和失败原因，但避免记录敏感凭证。

### 7.3 待确认状态伪造

风险：客户端修改邮箱、用户 ID 或重放旧的 pending 状态，导致向其他地址发送邮件或绕过流程。

控制：

- 优先使用服务端 session；
- 如果使用 URL token，必须签名、设置短过期时间并限定用途；
- 不接受客户端提交的用户 ID 或邮箱作为可信身份；
- 重发前再次从数据层确认账户状态为未确认。

### 7.4 确认链接泄露

风险：确认 token 出现在浏览器历史、日志、Referer 或第三方分析系统中。

控制：

- 确认成功后立即跳转到不带 token 的 URL；
- 不在页面、日志或 flash 中输出完整 token；
- 生产环境使用 HTTPS；
- 确保 token 具有过期和一次性消费语义。

### 7.5 误把其他 confirmation 错误当成普通注册确认

当前系统还可能出现密码重置、OAuth/OIDC identity link 等 confirmation 场景。`UnconfirmedUser`、`ConfirmationRequired` 和 `CannotConfirmUnconfirmedUser` 语义不同，控制器应分别处理，不能用一个宽泛的错误匹配把它们全部跳到同一个页面。

## 8. 页面与路由边界

`/auth/please-confirm` 必须位于普通 browser pipeline 中，但不能放在要求已认证用户的 `live_session` 中。它可以被未登录用户访问，也应避免被 `live_no_user` 限制，以免失败回调携带的状态被已有 session 规则干扰。

页面只允许以下操作：

- 查看确认说明；
- 重新发送确认邮件；
- 返回登录页。

不应允许未确认用户通过该页面访问设置、业务数据、OAuth consent、管理后台或任何会改变账户状态的普通业务 action。

## 9. 后续落地拆分

实现时建议拆成几个独立步骤：

1. 在注册 LiveView 和登录 LiveView 分别确认 `UnconfirmedUser` 的表单错误结构。
2. 决定专属页面是从 LiveView 内部跳转，还是统一改为 controller 路径；如果保留默认 LiveView 登录表单，需要自定义表单组件处理 `Form.submit/2` 的 `{:error, form}`。
3. 对 controller failure callback 增加专门分支，并为 LiveView 表单增加对应处理。
4. 只有在密码已验证且未确认时，才创建 pending session；增加清理和过期策略。
5. 增加 `/auth/please-confirm` 页面及唯一 DOM ID。
6. 增加重发确认邮件的 context/action 封装，并绑定 pending session。
7. **TODO（安全调研，先于实现）**：调研 Elixir、Phoenix、Plug、Ash/AshAuthentication、Oban 及邮件供应商生态中成熟的限速、幂等、分布式计数和 abuse prevention 方案。重点验证多节点部署、Redis/数据库依赖、故障降级、时钟偏差、清理策略和可观测性，禁止先自行实现未经评估的内存计数器。
8. **TODO（安全调研，先于实现）**：调研审计日志和安全事件记录的成熟方案，定义 OIDC server 所需的事件模型、字段最小化、关联 ID、时间精度、保留期限、脱敏、访问控制、篡改防护和告警策略。审计数据不得记录密码、确认 token 或完整敏感凭证。
9. **TODO（威胁建模）**：在限速和审计方案确定前，覆盖邮箱轰炸、账户枚举、确认 token 重放、session 固定/伪造、跨租户关联、分布式竞态、邮件供应商失败和日志泄露等场景。
10. 根据调研结果设计并评审限速、审计和告警方案，优先形成安全边界和失败行为，再实现代码。
11. 增加控制器、LiveView、pending session、确认链接和邮件重发测试。
12. 运行 `mix precommit`，确认格式化、编译、测试和静态检查全部通过。

本文同时记录方案和当前初版实现状态；限速、审计及 OAuth/OIDC 全面门禁尚未实现。

## 10. 认证场景矩阵

本项目定位为 OIDC Server，确认状态不能只保护密码登录。所有能够建立本地认证状态、签发 token，或产生 OAuth/OIDC 授权结果的入口，都必须满足同一个安全不变量：未确认用户不得获得有效的应用认证能力或 OAuth/OIDC artifact。

| 场景 | 主要入口 | 认证/授权结果 | 当前确认机制 | 需要验证的保护点 |
| --- | --- | --- | --- | --- |
| 普通密码登录 | `/sign-in`，LiveView `Form.submit/2` | sign-in token、session | password strategy 的 `require_confirmed_with` | LiveView 错误不能只显示通用错误，应能进入 `/auth/please-confirm`；不得生成 sign-in token |
| 注册后的自动登录 | `/register` / password register action | 新用户、可能的 token/session | registration action 的 `RequireConfirmedChange` | 账户可以创建以接收邮件，但不得把未确认注册当作已登录成功 |
| 独立 sign-in token | `sign_in_with_token` | 新认证 token、session | token preparation 再次检查 `confirmed_at` | token 失败时不得建立 session；确认检查、token 消费和错误行为要明确 |
| Magic Link 登录 | `/auth/user/magic_link` | session | `auto_confirm_actions` 包含 `:sign_in_with_magic_link` | 合法 Magic Link 才能证明邮箱并自动确认；必须防重放、过期和错误 action 使用 |
| 外部 OAuth/OIDC 登录 | 未来 provider strategy | 本地用户、session、identity link | 当前尚未配置外部 provider | 明确 `email_verified` 信任边界、upsert、identity link 和账户接管防护 |
| OAuth Server 授权入口 | `/oauth/authorize` | authorization code | 当前主要依赖 session actor | 未确认 actor 不得进入授权或 consent 页面，不得签发 code |
| OAuth Server consent | `/oauth/authorize` POST approve | consent、authorization code | 当前使用当前 actor 直接 approve | approve 前必须再次确认用户状态，不能只依赖进入页面时的检查 |
| OAuth token exchange | `/oauth/token` | access token | 依赖授权码流程 | 只有已确认用户创建的有效 code 才能兑换；需验证 code 与用户状态绑定 |
| OIDC 授权入口 | `/oidc/authorize` | OIDC authorization code | 当前检查 actor，但未见显式 confirmed 检查 | 未确认 actor 不得展示 consent 或签发 code |
| OIDC token endpoint | `/oidc/token` | access token、ID token | 根据 authorization code 读取用户 | 必须确保 code 对应已确认用户；不得为未确认用户签发 ID token |
| OIDC userinfo | `/oidc/userinfo` | 用户 claims | Bearer token + `openid` scope | 未确认用户不能获得有效 bearer token；`email_verified` 必须与确认状态一致 |
| Bearer/API 登录 | `load_from_bearer` 及 API 路由 | API actor | 当前依赖 bearer token 解析 | 新签发 token 必须来自已确认用户；API 业务入口不能绕过确认门禁 |

### 10.1 统一安全不变量

实现和测试必须验证以下规则：

1. `confirmed_at == nil` 的用户不能获得正常应用 session。
2. `confirmed_at == nil` 的用户不能获得新的 sign-in token、remember-me token 或 bearer token。
3. 未确认注册可以创建账户和发送确认邮件，但不能表现为已登录成功。
4. 未确认用户不能进入 OAuth/OIDC consent 页面。
5. 未确认用户不能 approve consent。
6. 未确认用户不能获得 authorization code、OAuth access token 或 OIDC ID token。
7. 未确认用户不能通过 `/oauth/userinfo` 或 `/oidc/userinfo` 获取用户信息。
8. OAuth/OIDC 的 `email_verified` claim 必须严格反映确认状态，不能仅因为存在邮箱就返回 `true`。
9. 所有 token、session 和授权码的错误响应不能泄露密码、确认 token 或内部错误细节。
10. `/auth/please-confirm` 只能提供确认说明和重发确认邮件能力，不能成为普通业务入口。

### 10.2 第 3 步前的检查清单

在开始实现前，需要逐项确认：

- [ ] 普通密码登录的 LiveView 错误是否能识别 `UnconfirmedUser`。
- [ ] 注册 LiveView 是否能区分“账户已创建但待确认”和“注册真正失败”。
- [ ] `sign_in_with_token` 是否在 token 消费和新 token 生成前后都保持确认保护。
- [ ] Magic Link 的自动确认是否只适用于合法、未过期、未重放的 token。
- [ ] 未来外部 OAuth/OIDC provider 的 `email_verified`、upsert 和 identity link 规则是否已定义。
- [ ] `/oauth/authorize` 是否拒绝未确认 actor。
- [ ] OAuth consent approve 是否在签发 code 前再次检查确认状态。
- [ ] `/oauth/token` 是否验证 authorization code 对应的用户仍满足确认要求。
- [ ] `/oidc/authorize` 是否拒绝未确认 actor。
- [ ] `/oidc/token` 是否不会为未确认用户生成 access token 或 ID token。
- [ ] `/oauth/userinfo` 和 `/oidc/userinfo` 是否只能接受已确认用户的有效 bearer token。
- [ ] API pipeline 是否不存在绕过认证策略的直接 actor 注入路径。
- [ ] 所有新建 session、sign-in token、authorization code 和 bearer token 的来源是否可追溯。
- [ ] 每个场景是否都有未确认、已确认、错误 token、重复 token 和跨入口测试。

## 11. 第 3 步范围

第 3 步只设计，不实现代码，内容包括：

- 统一的 confirmed-user 门禁边界；
- `/auth/please-confirm` 的 pending session 数据结构、过期和清理语义；
- LiveView、controller、API、OAuth 和 OIDC 各入口的错误处理策略；
- 哪些检查放在 Ash action/preparation，哪些检查放在 Phoenix Plug/controller；
- 新建 token、session、authorization code 和 consent 的安全不变量测试计划。

## 12. 第 3 步设计

### 12.1 设计原则

确认状态检查分为两层，不能只依赖其中一层：

1. **认证结果产生层**：Ash Authentication 的 strategy/action/preparation 负责阻止未确认用户产生新的登录 token、session 或其他认证结果。
2. **资源访问与协议层**：Phoenix Plug、controller 和 OAuth/OIDC service 负责阻止未确认 actor 使用已有认证材料访问应用、consent 或协议 endpoint。

两层都必须存在。第一层防止新凭证产生，第二层防止未确认 actor 通过 API、OAuth Server、OIDC Server 或业务路由获得能力。

### 12.2 统一 confirmed-user 判断

设计一个只表达业务事实的集中判断入口，例如：

```text
confirmed_user?(user) -> true | false
```

要求：

- 只把非空 `confirmed_at` 视为已确认；
- 不接受客户端提交的 `confirmed_at`；
- 不根据邮箱格式、密码验证结果或 token 存在性推断确认状态；
- 调用方根据协议场景决定返回 HTML redirect、认证失败、OAuth error 或 HTTP 401/403；
- 该判断不能替代 Ash policy，也不能绕过资源授权。

如果数据层查询可能隐藏 `confirmed_at`，认证 action 应继续使用 Ash Authentication 内置的 confirmation calculation；协议层在已经取得可信用户记录后再使用集中判断。

### 12.3 pending confirmation session

`/auth/please-confirm` 只接收服务端创建的 pending 状态，不接收客户端指定的用户身份。

建议保存的最小字段：

```text
pending_confirmation: %{
  user_id: user.id,
  email: user.email,                 # 仅用于展示/发送，必要时可不保存
  source: :password_login | :registration | :oauth_authorize,
  return_to: safe_local_path | nil,
  created_at: unix_seconds,
  expires_at: unix_seconds,
  nonce: random_value
}
```

安全要求：

- 只在密码已验证且确认状态为空时创建；注册场景只能在账户创建成功且未确认时创建；
- 不保存密码、完整认证 token、OAuth authorization code 或外部 provider token；
- `user_id` 和邮箱从服务端认证结果取得，不信任表单、query string 或 hidden input；
- `return_to` 只能是经过校验的本站相对路径，禁止开放重定向；
- 设置短过期时间，确认完成或登出时清理；重发成功后保留 pending 状态，但应更新发送时间/一次性重发状态（具体限速策略留待安全调研）；
- pending session 不能被当作登录 session、Ash actor 或 OAuth actor；
- 重发前重新读取用户并确认仍为未确认状态；
- session 中不应存储完整邮箱，除非确认 cookie/session 的加密、签名和隐私要求已验证。默认优先保存 `user_id`，展示时从服务端读取邮箱。

对于本项目当前的密码已验证/注册成功流程，可以在安全 session 中同时保存邮箱，用于确认页展示，避免重复查询。`user_id` 仍是重发时的可信身份来源，邮箱不能由客户端重新提交。确认页没有有效 pending session 时，应清理状态并重定向到 `/sign-in`，而不是展示空的确认页面。

### 12.4 各入口的行为设计

#### 普通密码登录

普通密码登录初版优先使用普通 controller POST，而不是让默认 LiveView 登录组件在浏览器内预提交并消费认证错误：

```text
登录表单
  -> POST controller authentication route
  -> AuthController.success/4 或 failure/3
  -> 统一处理已确认、未确认和普通认证失败
```

选择 controller POST 的背景：

- 当前默认 `AshAuthentication.Phoenix` LiveView 登录表单会在 `Form.submit/2` 内执行读取和认证；
- 失败时它把错误保存在表单中并重新渲染，默认错误转换会将认证失败统一显示为“邮箱或密码错误”；
- 这会绕过 `AuthController.failure/3`，使 `UnconfirmedUser` 无法在统一的 HTTP 认证失败入口中处理；
- 方案 A 需要在确认密码成功但账户未确认时创建 pending session，并跳转到 `/auth/please-confirm`；
- controller POST 可以让普通登录、注册后的失败处理和后续 pending session 流程拥有清晰、可测试的 HTTP 边界。

因此，初版登录流程设计为：

```text
controller failure/3 识别 UnconfirmedUser
  -> 创建 pending session
  -> 跳转 /auth/please-confirm
```

普通错误仍返回通用的邮箱/密码错误，不创建 pending session。

如果未来必须保留 LiveView 的即时预校验体验，则需要自定义登录组件，显式处理 `Form.submit/2` 的 `{:error, form}`，并调用与 controller 相同的 pending session 服务；不能只通过 `AuthOverrides` 修改样式来实现。

controller 登录页仍必须保留原有认证能力，包括密码重置入口和 Magic Link 请求入口。切换登录页面渲染方式不能导致这些认证策略丢失。

#### 注册

注册成功创建未确认用户时，不应调用普通登录成功流程。应将注册结果分类为：

```text
账户已创建 + 等待确认
  -> 创建 pending session
  -> 跳转 /auth/please-confirm
```

如果账户创建失败，则保留注册错误，不创建 pending session。

#### sign-in token / remember-me token

任何 token 登录或 remember-me 恢复流程都必须在建立 session 之前确认用户状态。未确认时：

- 不设置 actor；
- 不建立 session；
- 不签发新 token；
- 对浏览器请求跳转 `/auth/please-confirm` 仅限于存在可信 pending 状态的情况；
- 对 API 请求返回标准认证失败，不返回 HTML 页面。

#### Magic Link

Magic Link 是邮箱所有权证明路径，可以通过现有 `auto_confirm_actions` 自动确认，但必须继续依赖 token 的签名、过期、用途和一次性消费校验。它不应复用普通密码登录的 pending session。

#### 未确认用户的密码重置

当前 confirmation add-on 将 `:reset_password_with_token` 配置在 `auto_confirm_actions` 中。因此未确认用户可以通过合法的密码重置流程恢复账户：请求重置邮件、提交有效且未过期的一次性 token、设置新密码，成功后自动确认账户。该流程必须继续保留在登录页，并与普通确认邮件流程区分；密码重置 token 本身不能被当作普通登录 session 复用。

#### OAuth/OIDC provider 登录

未来接入外部 provider 时，provider 登录结果必须先经过统一的本地账户确认/identity-link 规则，再决定是否创建本地 session。不能仅凭未验证的 provider email 自动确认本地账户，也不能把“provider 登录成功”默认等同于“本地邮箱已确认”。

#### OAuth Server / OIDC Server 授权

授权入口、consent 页面、approve action 和 code 签发都要检查 confirmed-user：

```text
没有 actor
  -> 进入普通登录流程

有 actor 且未确认
  -> 不展示 consent
  -> 不 grant consent
  -> 不签发 authorization code
  -> 浏览器流程进入 /auth/please-confirm

有 actor 且已确认
  -> 继续 consent / code 流程
```

协议错误不能把内部 `UnconfirmedUser` 结构直接返回给 OAuth client。对于浏览器授权流程，应保留安全的 `return_to`；对于 token endpoint 和 userinfo，应返回协议规定的错误。

#### OAuth/OIDC token endpoint 与 userinfo

token exchange 不能只验证 authorization code 的格式和签名，还要确认 code 关联的用户仍为已确认状态。userinfo 在 bearer token 认证成功后仍应确保 actor 满足确认要求，避免某个非预期 token 来源绕过授权层。

### 12.5 门禁放置位置

建议的放置顺序：

```text
Ash strategy/action/preparation
  -> 阻止未确认用户产生认证结果

browser pipeline / session actor gate
  -> 阻止未确认 actor 访问应用和 OAuth consent

API bearer gate
  -> 阻止未确认 actor 访问 API/userinfo

OAuth/OIDC service boundary
  -> 阻止未确认用户获得 code/access token/ID token
```

不能只在 router 的某一个 scope 加 Plug，因为 OAuth Server 的 protocol router、OIDC controller、API pipeline 和 LiveView session 的边界不同。所有入口应复用同一个 confirmed-user 判断，但每个协议必须保留自己的错误响应格式。

### 12.6 第 3 步产出的测试设计

实现前应准备以下测试组：

- 未确认密码登录：错误被识别，创建 pending session，不创建认证 session；
- 已确认密码登录：正常建立 session；
- 未确认注册：账户存在、确认邮件可发送、没有登录 session；
- sign-in token 和 remember-me：未确认时不能恢复登录；
- Magic Link：合法 token 自动确认并登录，错误/过期/重放 token 失败；
- 未确认用户访问 `/oauth/authorize` 和 `/oidc/authorize`：不能展示或提交 consent；
- 未确认用户 approve consent：不能签发 authorization code；
- 未确认用户 code exchange：不能获得 access token 或 ID token；
- 未确认用户 userinfo：返回协议规定的认证失败；
- 已确认用户的 OAuth/OIDC 全流程不受影响；
- `return_to` 不能形成开放重定向；
- pending session 过期、伪造、跨用户、重复使用时均失败。

第 3 步到此为设计阶段，不在本步实现 pending session、Plug、LiveView 组件或 OAuth/OIDC 门禁。

## 13. 最新结论与后续步骤

目前不继续扩展复杂的统一认证框架。下一步按最小闭环推进：

1. **验证当前初版**：补充普通密码登录、未确认登录、注册、确认成功、重发和密码重置的行为测试，确认 pending session 生命周期符合预期。
2. **观测注册流程**：确认 controller POST 注册在不同错误、邮件发送和确认页访问条件下保持预期；不再维护一套容易吞掉 `UnconfirmedUser` 的注册 LiveView 表单。
3. **单独评估 OAuth/OIDC 门禁**：先针对 `/oauth/authorize`、`/oidc/authorize`、token exchange 和 userinfo 编写未确认用户测试，再根据测试结果实现最小的协议边界检查。不能先加入未经验证的全局 Plug。
4. **最后调研限速与审计**：在认证行为稳定后，再调研 Elixir/Phoenix/Ash/Oban 生态的成熟方案，形成独立设计后实现。
5. 每完成一个步骤，单独运行相关测试和 `mix precommit`；不把多个安全边界改动合并到一个步骤中。

当前推荐的停止点是第 1 步：先用测试观测现有实现，不立即增加新的 OAuth 门禁代码。
