# Authx 应用

基于 phoenix + ash的 OIDC server

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