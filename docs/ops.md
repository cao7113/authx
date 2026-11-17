# Ops

## Development accounts

After setting up the development database, run `mix dev.seed` to create the
confirmed users `dev@l.h` and `admin@l.h`. Both use the public development
password `password123456`; `admin@l.h` receives administrator access. The
development sign-in page fills in the administrator credentials by default.

Running the task again resets both users' passwords. These credentials are for
local development only; never use them in a publicly accessible environment.

## Administrator access

After running the database migrations and registering a user, bootstrap the first
administrator from a trusted IEx session:

```elixir
Authx.Accounts.Admins.bootstrap("admin@authx.s")
```

Bootstrap returns `{:ok, user}` on success and is unavailable once an
administrator exists. Administrators can grant or revoke access from **Admin →
用户管理**. The last administrator cannot be removed. Ash Admin, LiveDashboard
(`/admin/dashboard`), and Oban are restricted to administrators; the Dev menu
and mailbox preview are only available in development.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).
