# Authx 应用

基于 phoenix + ash的 OIDC server

生产化计划和上线门禁见 [OIDC 生产化与上线计划](oidc-production.md)。
管理员与客户端注册的设计见 [OIDC 客户端管理](oidc-client-management.md)。
用户自助撤销 OIDC 授权的设计见
[用户侧 OIDC 授权撤销](oidc-consent-revocation.md)。
scope 的语义与实现见 [OIDC Scope 实现说明](oidc-scopes.md)。
ID Token 的签名密钥、JWKS 发布与轮换限制见
[OIDC ID Token 签名密钥](oidc-signing-keys.md)。
公开客户端的威胁模型与其他客户端认证方式的增强建议见
[OIDC 客户端认证与公开客户端威胁模型](oidc-client-authentication.md)。
浏览器插件接入与业务 API 授权模型见
[浏览器插件接入 Authx OIDC](browser-extension-oidc.md)。
本地 demo 与 foo 的接入步骤分别见 [OIDC client demo](client-demo.md) 和
[Authx Foo 接入 Authx OIDC](authx-foo-oidc-client.md)。Eim 作为本地 OIDC
客户端的迁移方案见 Eim 仓库的 `docs/OIDC客户端迁移方案.md`。

## todo

- 多 OIDC providers 能否是否可以归并到同一个 统一user

## 背景和目标

多个基于elixir + phoenix + ash的 web应用，如 eim, slink等，不想在每个应用里设计维护认证系统

希望方案基于 elixir 生态，并适用接入多语言栈应用客户端，支持浏览器插件客户端

分步实现

### 第一版MVP

- 确认 elixir技术框架
- 支持 password/magic-link
- oauth2 server

### 联合登录

- github
- apple
- google

## 基础知识

- OAuth2 & OIDC
- OIDC server & client
- IDP（Identity Provider）

成熟的开源 OIDC 认证服务器（如 Keycloak、Zitadel 或 Authelia），由它们专门负责 OIDC 协议栈、会话管理和 JWKS 签发