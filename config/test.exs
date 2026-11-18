import Config

config :authx, Oban, testing: :manual
config :authx, token_signing_secret: "5eZG2YfG6iDzeKs9b8am0zBUR6Wf0Tkl"

config :authx,
  oauth2_issuer_url: "http://localhost:4000",
  oauth2_resource_url: "http://localhost:4000",
  oidc_resource_url: "http://localhost:4000/oidc/userinfo",
  oauth2_signing_secret: "test-oauth2-signing-secret-not-for-production"

config :bcrypt_elixir, log_rounds: 1

config :ash,
  policies: [show_policy_breakdowns?: true],
  keyset_signing_secret: "oADxi5OUhlSRJNSgx6LpaSJd1fRFC4OhP0lM3dOwWy4",
  disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :authx, Authx.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "authx_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :authx, AuthxWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "b+c/pla280ZcVPARZKaaylgYT9WLaBcM/2dwwkfTVup8pcsHfxG9CmSx7QAc+cwi",
  server: false

# In test we don't send emails
config :authx, Authx.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
