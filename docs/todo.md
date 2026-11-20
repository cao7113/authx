# todos
- user email should verified to go further login!!!
- admins 单独建表？ 代码优化
  fix：原来的流程，admin 注册后默认没有 confirmed， 2026.11.19 手工在 authx.s上添加 confirmed_at字段，手工测试 eim.s浏览器插件登录(问题：浏览器流程和插件流程不一致，浏览器没有验出 email unverfired 问题，插件验出来了，咋回事呢？？？)

- 应该限制 客户端（如 eim）改 user-email，应该仅用于展示和从 authx 同步，因为 要不对齐策略可能就会出现问题！！！

- 取消授权 支持（明确的未退出 authx 说明；authx 登录有效时间是多少，有效期问题）

- auth audit logs https://ash-authentication.hexdocs.pm/audit-log.html

- `token_endpoint_auth_method=none`，支持其他类型，如 secret 的
- developer console
- link github，apple...