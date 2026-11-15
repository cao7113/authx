# Authx 应用

```
mix igniter.install ash_authentication_oauth2_server
```

## 需求描述

多个基于elixir + phoenix + ash的 web应用，如 eim, slink等，不想在每个应用里设计维护认证系统

希望方案基于 elixir 生态，并适用接入多语言栈应用客户端，支持浏览器插件客户端

分步实现

### 第一版MVP

- 确认 elixir技术框架
- 支持 password/magic-link

### 支持联合登录

- github
- apple
- google

## 基础知识

- OAuth2 & OIDC
- OIDC server & client