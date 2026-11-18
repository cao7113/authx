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

## Developer and client operations in production

Operations are called from a remote shell:

```bash
bin/authx remote
```

Operational entry points live in `Authx.Ops`, which resolves users and
developers from emails and composes the domain calls. Emails always identify an
Authx **user**. A developer has no email of its own; use the email of the user
that developer access was granted to.

Grant developer access:

```elixir
iex> Authx.Ops.grant_developer("dev@example.com", "admin@example.com")
{:ok, %Authx.Developers.Developer{}}
```

Register a client for that developer, or verify that an existing client still
matches the given settings:

```elixir
iex> Authx.Ops.ensure_client(
...>   "dev@example.com",
...>   "Foo",
...>   ["https://foo.example/callback"]
...> )
{:ok, %Authx.Oauth.Resources.Client{}}
```

`ensure_client` never overwrites an existing client. If the name already exists
with different settings, it returns `{:error, {:client_mismatch, details}}` so
the conflict is resolved explicitly. The client id is always generated. An
optional `scope` can be supplied as an option; all other metadata uses the
shared defaults in `Authx.Oauth.Clients.default_attrs/2`.

Look up a developer directly when you need the record:

```elixir
iex> Authx.Developers.find_developer_by_user_email("dev@example.com")
%Authx.Developers.Developer{}

iex> Authx.Developers.fetch_developer_by_user_email("someone@example.com")
{:error, :not_found}
```

The domains (`Authx.Developers`, `Authx.Oauth.Clients`) operate on records and
are what the developer console uses. `Authx.Ops` is the remote-shell and
mix-task layer. All mutations run through Ash policies with the resolved user or
developer as the actor; only the email lookup bypasses read authorization.
`mix dev.seed` uses the same entry points for local development.

## OIDC ID Token signing key

Generate a production signing key (RSA-2048, mode `0600`, never overwrites an
existing file):

```sh
mix gen.oidc.private_key /secure/path/authx_oidc_private_key.pem
# AUTHX_OIDC_PRIVATE_KEY_FILE=/Users/rj/dev/elab/authx/_local/authx_oidc_private_key.pem
```

Mount the file into the release and set `AUTHX_OIDC_PRIVATE_KEY_FILE` to its
path. Keep it stable across restarts. See
[OIDC ID Token signing keys](oidc-signing-keys.md) for the key lifecycle and
current rotation limitations.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).
