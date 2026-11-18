# OIDC 身份与客户端管理

## 定位与原则

Authx 是面向**超级个人开发者**的独立身份服务：一个人开发和运营多个
应用，希望统一用户身份，同时保持应用接入的安全和日常管理的简洁。
安全优先，但不为了假设的团队场景提前建设复杂平台。

目标将**管理员**和 **developer** 作为独立角色：管理员管理 Authx 本身
的资源并手动授权用户成为 developer；developer 管理自己接入 Authx 的
应用，并有自己的前端控制页面。客户端归属于 developer。同一个现有
Authx 用户可同时拥有两种角色，初期通常由同一个人承担。

**评价：** 这个划分合理：身份、权限和操作入口都与职责一致，同一人使用
也不必共享管理员权限给开发者流程。代价是要实现角色授权、独立控制台、
所有权校验和已有数据迁移。首版不引入组织、多所有者、应用审核或
开发者自助注册；以后可以按需扩展 API 和工具。

文中「当前」表示代码已具备的能力；「建议」和「待实现」不是已有功能。
本地试运行不等于面向公网的正式生产。生产安全门禁另见
[OIDC 生产化与上线计划](oidc-production.md)。

## 概念和角色

### 人和账号：Authx 内部角色

- **Authx 用户**：在 Authx 有账号、可以向 Authx 认证的人。代码使用
  `Authx.Accounts.User` 表示账号，其 `role` 当前为 `user` 或 `admin`。
- **普通用户**：使用 Authx 登录和授权的用户，不因登录而获得开发者或
  管理员权限。当前代码的 `role=user` 表示非管理员；目标模型中一个
  用户也可另外具有开发者身份。
- **管理员（admin）**：Authx 中 `role=admin` 的用户，负责 Authx 运维、
  系统资源、用户及角色授权管理，包括手动授予和撤销 developer 资格。
  admin 职责不隐含 developer 身份，也不是默认的客户端所有者；管理员
  账号须另行获授权才能使用 developer 功能。
- **客户端应用开发者（developer）**：开发、配置和维护接入应用的人或
  团队。目标首版以经管理员授权的现有 Authx 用户为主体，通过专用控制台
  管理自己名下的客户端；不需要再注册另一个登录账号。当前代码尚无独立
  developer 角色、开发者控制台及客户端归属。
- **客户端用户**：使用某个接入应用的人。使用 Authx 登录时，此人也是
  OIDC 的最终用户；应用可以为其建立自己的用户记录、会话和业务权限。
  客户端用户与 Authx 用户可对应同一个人，但它们属于不同系统的数据，
  不必使用相同的本地用户 ID。管理员也可以作为普通最终用户登录自己的应用。

Authx 的管理员权限不会自动成为客户端应用的管理员权限；反过来，应用
内的管理员也不会因此成为 Authx 管理员。各应用自行决定业务授权。
「唯一管理员」是当前使用方式，不是代码强制的数量限制；现有角色管理
支持为其他用户授予管理员权限。

### 协议参与方

- **身份提供方 / 授权服务器（OpenID Provider / Authorization Server）**：
  Authx 负责认证最终用户、征求授权、签发授权码和令牌，并发布 discovery
  与 JWKS。
- **最终用户 / 资源所有者（End-User / Resource Owner）**：操作浏览器、
  在 Authx 认证并决定是否授权的人；并不等同于应用开发者。
- **客户端 / 依赖方（OAuth Client / OIDC Relying Party，RP）**：请求
  登录或用户信息的应用实例，使用注册得到的 `client_id` 标识。它不是
  一个 Authx 用户账号，也不是人；`client_id` 本身不是秘密或身份凭据。
- **用户代理（User-Agent）**：承载登录和重定向的浏览器等；它不是
  OIDC 客户端注册记录。
- **资源服务器（Resource Server）**：验证 access token 并提供受保护资源
  的服务。当前 OIDC 场景中的 UserInfo 端点由 Authx 提供；其他业务 API
  是否作为资源服务器及其授权方式需单独设计。

`openid` 是 OIDC 身份请求；`email` 请求邮箱相关声明；`profile` 请求标准资料
声明（当前下发 `updated_at`）。scope 的完整语义见
[OIDC Scope 实现说明](oidc-scopes.md)。
ID Token 供客户端验证用户身份，access token 用于访问指定资源；
两者不能互换。客户端按已验证的 `(issuer, sub)` 识别外部身份，不应仅
按 email 自动合并账号。当前实现发布 `public` subject；应用内部用户 ID
及角色仍由各应用管理。

## 关系和流程

```text
管理员 ──手动授权──> 已有 Authx 用户 + developer 角色
                              │
                       开发者控制台
                              └─注册并拥有──> 客户端记录（client_id、回调、scope）

最终用户 ──使用──> 客户端应用（RP） ──授权请求──> Authx（OP）
   │                     ▲                         │
   └──── 登录并同意授权 ──┴────── 授权结果 ─────────┘
                         │
                         └─ 验证身份后建立应用自己的用户记录和会话
```

1. **目标：** 用户先使用现有 Authx 认证体系登录；管理员在后台手动授予
   其 developer 角色。该用户通过开发者控制台注册应用并成为其所有者。
   注册后立即可用，没有应用审核，也不等同于用户已同意授权。
   **当前：** developer 角色与客户端归属已落地，注册须以开发者身份
   （`Authx.Developers.Developer` 作为 actor）执行；开发者控制台尚未实现，
   本地开发由 `mix dev.seed` 注册，生产环境在 remote shell 中用
   `Authx.Ops.ensure_client/3` 注册（见 [Ops](ops.md)）。
2. 最终用户从应用发起登录，应用带 `state`、`nonce` 和 PKCE 跳转 Authx。
   用户的 Authx 凭据提交给 Authx，而不是客户端应用。
3. Authx 校验客户端和回调，必要时让用户登录并同意所请求的 scope；已有
   覆盖该 scope 的 consent 时，现有实现可能跳过同意页面。
4. 应用在回调校验 `state`，服务端或客户端使用 verifier 兑换授权码；
   验证 ID Token 的签名、issuer、audience、时效及 nonce。
5. 应用按 `(issuer, sub)` 关联本地账号并建立本地会话。退出应用只结束
   应用会话，不自动退出 Authx，也不等于撤销 consent。

## 当前架构与评价

- **账号和授权**：`Authx.Accounts.User` 区分 `user` 和 `admin`；
  已引入独立的 `Authx.Developers` 领域（`Developer` 资源），支持管理员手动
  授予现有用户 developer 资格并按 `user_id` / `email` 查询（撤销功能待停用语义明确后实现）；
  `OauthClient` 保存客户端并通过 `developer_id` 归属某个 developer，
  `OauthConsent` 按用户和客户端保存 scope。
  `demo/` 使用独立数据库，并以 `(issuer, sub)` 关联本地身份。
- **管理入口**：`/admin` 已挂载 Ash Admin，HTTP 入口和 LiveView 均检查
  管理员身份；`Authx.Accounts` 已向 Ash Admin 显示。生产环境没有 Mix，
  开发者授权与客户端操作在 remote shell 中通过 `Authx.Ops` 的
  `grant_developer/2`、`ensure_client/2` 执行（见 [Ops](ops.md)）；`Authx.Ops` 负责按 email 解析用户和 developer，再调用
  `Authx.Developers` / `Authx.Oauth.Clients`，这些操作仍以解析出的
  admin/developer 作为 actor 走策略。
  普通用户不应能进入管理入口。
- **客户端归属**：`Authx.Oauth.Resources.Client` 的 `developer_id` 为必填外键，
  每个客户端恰好属于一个 developer。创建只经过 `Authx.Oauth.Resources.Client` 的
  `:register` action：actor 必须是当前有效的 `Developer`，归属由 actor
  决定且不能作为输入提交（`developer_id` 不在 accept 列表中，且不可写）。
  读取受策略限制为「当前有效 developer 且是该客户端属主」，因此不同
  developer 之间互不可见；普通用户、匿名访问和未获 developer 资格的管理员
  都看不到客户端。更新通过 `:update` action（上下文入口
  `Authx.Oauth.Clients.update/3`）执行，接受与注册相同的元数据字段，策略
  同样是「当前有效 developer 且为属主」；归属不能通过输入修改。创建和
  更新时都在资源 action 内校验安全关键项：回调 URI 必须是带 host 的
  HTTPS（或本机回环地址的 HTTP）且不含 fragment，
  `token_endpoint_auth_method` 只允许 `none`；grant_types、response_types
  和 scope 的限制仍待实现。
- **动态注册已关闭**：DCR（`/oidc/register`）与 CIMD 都已关闭，discovery
  不再发布 `registration_endpoint`，共享注册令牌机制已移除。共享令牌只能
  证明持有者被管理员告知过该凭据，无法识别是哪个开发者，不能满足归属或
  审计要求；面向自动化的按开发者凭据尚未设计。
- **客户端管理缺口**：当前没有修改与停用 action、停用状态和停用语义，
  也没有面向开发者的界面（控制台待实现）。删除 action 存在但没有任何
  主体被授权调用，不能把物理删除当作停用。

## 开发者与客户端需求

以下为**目标需求**；标注「**已实现**」的部分已在代码中落地，其余尚未实现，
实现形式和待确认事项见本节。

### 开发者身份

- **已实现** developer 是在**现有 Authx 用户**上被授予的独立角色，与 admin
  可同时存在；沿用现有登录、密码、magic link 和会话体系，不创建独立的
  开发者登录账号。「成为 developer」是增加权限，不是替换用户身份或原有角色。
- **已实现** 只有管理员可在后台手动授予已有用户的 developer 角色（撤销待
  停用语义明确后实现）；管理员本人也须显式获得该角色才能使用开发者功能。
  角色授予本身不是 OIDC 客户端注册，也不自动创建应用。
- 授权操作须校验当前真实管理员身份，并记录操作者、目标用户、操作和时间；
  不能由前端提交角色或自行指定授权人。敏感凭据不得进入审计记录。
  （授予记录已保存 `granted_by` 与 `granted_at`，面向管理界面的审计展示待实现。）
- **已实现** 不开放用户自行注册或申请 developer，不引入开发者审批或客户端审核。
  这不改变现有普通用户的注册和登录功能。
- 普通用户的登录、consent 和应用本地账号不依赖开发者资格。撤销开发者
  资格不应隐式删除 Authx 用户、客户端或历史授权记录。
- **已实现（最小数据模型）** 保留现有 `User.role` 的管理员语义，`Developer`
  与 `User` 一对一关联，`status` 表示授权是否有效（当前只会是 `active`）；
  客户端以 `developer_id` 引用该身份。以用户 ID 建立关联，不复制密码或
  邮箱作为登录凭据。
- **已实现** 不向互斥的 `User.role` 枚举加入 `developer`；身份记录和权限检查
  独立于是否显示控制台入口。

### 客户端归属与权限

- **已实现** 一个客户端有且仅有一个开发者所有者（`developer_id` 非空外键）；
  一个开发者可拥有多个客户端。归属只来自已认证的开发者身份（actor），
  不能提交任意 owner ID：`developer_id` 不在创建 action 的 accept 列表中，
  且在资源上不可写。组织归属、多所有者、委托和团队协作暂不实现。
- **已实现（读取与创建）** 开发者只能读取自己名下的客户端，策略要求 actor
  是当前有效的 developer 并且是该客户端属主；其他开发者、普通用户和匿名
  访问都读不到。客户端创建不需要管理员逐个审核；用户对客户端数据的
  consent 仍独立存在。修改与停用 action 待实现。
- **已实现** admin 不因拥有 admin 角色而自动作为 developer 创建或管理
  客户端：客户端策略不向 `User` actor 授权，未获 developer 资格的 admin
  也读不到客户端。管理员是否需要独立的应急查看、停用或归属转移能力须
  另行决定并审计，不能混同于开发者日常操作。
- 创建、修改和停用需在资源层执行相同的授权、归属和输入校验，覆盖
  开发者控制台及未来 API；仅限制页面入口不足以隔离数据。创建已实现
  归属与安全关键项校验（回调 URI、认证方式）；grant、response 和 scope
  校验以及修改、停用 action 待实现。
- 客户端停用、重新启用、所有者停用和归属转移对新授权、未兑换授权码、
  已签发令牌、consent 及应用本地会话的影响必须先定义并测试；不能把
  删除记录或撤销开发者资格等同于所有令牌和会话立即失效。

### 管理后台与开发者控制台

- **admin 后台：** 仅 admin 可访问，统一使用 Ash Admin
  完成用户管理、developer 角色的手动授予和撤销，以及 Authx 系统管理。
  具体复用方式取决于能否安全传递真实登录身份并实施资源策略。
- **开发者控制台：** 是首版必需的独立前端入口，不是 Ash Admin。
  仅已登录且 developer 角色有效的用户可访问；admin 若未获 developer
  角色也不能进入。普通用户和匿名用户不能进入或直接调用对应操作。
- **控制台首版能力：** 查看自己拥有的客户端列表和详情；注册新客户端，
  展示生成的 `client_id`、回调和允许的 scope；修改允许修改的配置；
  停用客户端。注册即生效，不出现审核或申请进度页面。
- 表单须对非法回调、超出支持范围的 scope、grant 和认证方式给出明确
  错误；修改及停用应有清晰确认和结果提示。client secret 仅在机密客户端
  支持后再设计，当前不应展示或承诺该能力。
- 控制台和后续 API/CLI 共用领域 action、可信 actor 与资源授权。页面、
  LiveView 连接和每次操作均须验证角色及所有权；撤销 developer 角色后
  已打开的控制台不能继续管理，不能仅通过隐藏菜单阻止访问。
- **后续 API 和工具：** 在相同角色及所有权模型上按需建设，不是首版
  控制台的前提，也不能绕过资源层授权。
- 面向自动化的注册和管理凭据应绑定具体开发者，可限制权限和有效期、
  单独撤销并记录操作主体。它与用户登录凭据、OIDC client secret、
  access token 和 `client_id` 不同；不向浏览器插件或前端分发高权限
  管理凭据。详细凭据机制及管理方式待设计。
- 当前本地共享注册令牌无法证明开发者身份。迁移到按开发者归属时须
  停用或替换该入口，或者仅将其保留为明确隔离的本地兼容机制；不得
  声称现有令牌已经提供开发者级授权、归属或审计。

### 待确认的产品决策

- 撤销 developer 资格后，名下客户端是否继续供最终用户登录；如不继续，
  如何处理其已有令牌和应用会话。Authx **用户账号被禁用**或用户撤销
  对客户端的 OIDC 授权，与 developer 角色撤销是不同事件；其立即失效的
  正式生产要求见生产化计划，当前尚未实现。
- 管理员跨开发者的具体管理权限，以及客户端归属转移的授权和审计流程。
- 将来是否允许开发者自助申请、创建团队、协作管理客户端或开放公共注册。
- 面向开发者的 API/CLI 和凭据机制何时进入范围；现阶段不把它们视为已实现。

## 分步实施与迁移建议

以下为**待实现**的方案；仅是实现顺序，不代表当前功能已存在。

1. 在现有用户认证体系上设计 developer 身份和资源策略（**已完成初始落地**：
   已建立独立 `Authx.Developers.Developer` 资源，实现管理员仅限的手动
   `:grant` 授予及按 `user_id`/`email` 查询，`User.role` 保持不变，
   撤销功能待停用语义明确后实现）。
2. 将 OAuth 2.1 / OIDC 协议资源从 `Accounts` 抽取至独立的 `Authx.Oauth` 领域，
   使 `Accounts` 聚焦于用户身份认证，为后续客户端所有权绑定和控制台建立清晰的领域边界。
3. 为客户端增加开发者归属。迁移前盘点现有客户端，由管理员明确指定其
   所有者；先创建和验证目标开发者，再回填归属并检查无遗漏，最后启用
   所有权约束。不得将无主记录自动分配给当前登录用户，也不能从共享
   令牌推断出开发者。
4. 保留既有 `client_id`、回调、授权码、consent 和用户身份；迁移测试
   要覆盖旧客户端登录及授权连续性。对迁移期间新增注册设置兼容策略：
   在回填与约束切换时暂停旧注册，或提供经过验证的受控归属写入；禁止
   产生新的无主客户端。上线前演练备份、失败处理和回滚，不盲目删除数据。
5. 在 `OauthClient` 上提供明确的开发者 action 和资源授权，满足所属
   客户端的列表、创建、修改和停用；在实施前确定停用和所有者状态变更
   的语义，不以物理删除替代停用。
6. 将客户端名称、回调 URI、允许的 scope、grant 和认证方式的校验放在
   所有入口共用的资源 action 或共享校验层。**部分完成**：回调 URI
   （HTTPS 或本机回环 HTTP、无 fragment）与认证方式（仅 `none`）已在
   `:register` action 校验；grant、response 和 scope 的校验待实现。
   动态注册已关闭；未来重新启用时必须复用同一校验层，不能绕过资源 action。
7. 增加使用现有会话的独立开发者控制台，完成列表、详情、创建、修改和
   停用流程，并对角色、所有权和操作结果实施校验；这是首版交付内容，
   不是后期可选门户。具体停用语义须在实现前确定。
8. 收敛 Ash Admin 暴露的资源、action 和字段，只提供必要的 Authx 系统
   和用户角色管理操作，避免把内部授权码、令牌或不适用的注册 action
   当作管理界面。当前资源 policy 只有认证交互 bypass，不能假定管理员
   或开发者已获得操作权限。
9. 设计并测试管理操作的授权和实际登录身份传递。Ash Admin 自带 actor
   选择与授权开关，不能把界面上选择的 actor 或关闭授权视为管理员身份
   证明；不能为了表单可用而对外开放 `authorize?: false` 或伪造认证内部
   context。保留管理员入口保护，并在资源层防止非授权主体绕过界面调用。
10. 以开发者会话完成控制台注册；按明确的兼容策略替换或关闭旧共享令牌
   注册入口。未来提供自动化 API/CLI 时，再接入绑定开发者的凭据。

**首版验收：**

- admin 可手动授予、撤销已有用户的 developer 角色；未获授权的 admin
  不能使用开发者控制台，获授权后可同时使用两个独立入口。
- developer 使用现有账号登录，可通过自己的控制台注册和管理客户端；
  注册立即生效，不涉及管理员审核。普通用户和匿名用户不得进入控制台或
  直接调用开发者操作；developer 不因此获得 admin 后台权限。
- 两个 developer 的客户端互不可见、不可修改或停用；伪造 owner ID
  无效。角色撤销后，已有连接和直接请求均不能继续执行开发者操作。
- 无效回调及不支持的配置被拒绝；修改和停用按事先确认的语义生效。
  测试须覆盖直接调用资源 action、前端入口和事件，未来 API 上线时再
  覆盖 API；旧数据迁移后 client ID 与登录流程保持不变。

## 当前本地协议能力

- `/oidc/*` 端点始终挂载并发布 discovery；生产部署需要配置 issuer、签名
  密钥和私钥文件后才能正常签发令牌。discovery 不发布
  `registration_endpoint`，也不提供动态注册。
- 不提供动态客户端注册：`/oidc/register` 路由与共享注册令牌机制已移除。
  客户端由当前有效的 developer 通过 `Authx.Oauth.Clients.register/3`
  （开发者控制台待实现）创建，归属由 actor 决定。
- 创建时校验回调 URI 与认证方式：回调必须是带 host 的 HTTPS，或
  `localhost` / `127.0.0.1` / `::1` 的 HTTP，且不允许 fragment；
  `token_endpoint_auth_method` 只允许 `none`。grant_types、response_types
  和 scope 的限制仍待实现。
- 仅支持 `authorization_code`、公开客户端 `none`、S256 PKCE，以及
  `openid` / `email` / `profile` scope；不签发客户端密钥或 OIDC refresh token。
  此限制同样适用于服务端应用的本地测试。
- 授权请求必须使用已登记的完整回调地址。注册信息存入 Authx 数据库；
  developer 资格由管理员手动授予，没有可配置的应用审核。

## 当前本地开发使用

本地开发使用现有开发数据库、用户和开发者身份，不需要注册令牌。首次
准备（创建数据库、种子用户、给开发管理员授予 developer，并注册本地
demo 客户端）：

```sh
mix dev.setup
```

`mix dev.seed` 注册的 demo 客户端由 `config/dev.exs` 的 `:demo_client_app`
配置：id 固定为 `00000000-0000-7000-8000-000000000001`，默认回调为
`http://localhost:4001/auth/user/authx/callback`，可用
`AUTHX_DEMO_CALLBACK` 覆盖。同一任务还会注册 `:foo_client_app` 配置的本地
foo 客户端（id `00000000-0000-7000-8000-000000000002`，默认回调
`http://localhost:4002/auth/user/authx/callback`，可用
`AUTHX_FOO_CALLBACK` 覆盖），接入步骤见
[Authx Foo 接入 Authx OIDC](authx-foo-oidc-client.md)。重复执行会复用这些
客户端并校验配置一致；若存在不同 id 的同名客户端或配置不一致，任务会
报错要求先检查或删除。

启动服务（开发环境已默认开启本地 OIDC 端点）：

```sh
mix phx.server
```

开发环境 issuer 固定为 `config/dev.exs` 中的 `http://localhost:4000`；如需
改用 `https://authx.s`，请修改该配置，并自行配置本机 DNS、可信证书和仅
本机可访问的代理。不要将开发默认账号或密钥暴露到公网。

固定的 `client_id` 可直接用于发起 authorization code + S256 PKCE 流程。
客户端登录示例见 [OIDC client demo](client-demo.md)。客户端认证方式的威胁
模型与扩展建议见
[OIDC 客户端认证与公开客户端威胁模型](oidc-client-authentication.md)；
浏览器插件的登录与 API 授权模型见
[浏览器插件接入 Authx OIDC](browser-extension-oidc.md)。

## 后续工作

先确认待定的生命周期和管理员应急操作边界，再按上面的顺序落实 developer
角色、客户端归属、管理员手动授权及独立开发者控制台。API/CLI 后续按需
实现；正式生产前仍须完成 [生产化计划](oidc-production.md) 中的安全门禁。
