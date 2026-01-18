import Config

test_partition = System.get_env("MIX_TEST_PARTITION")

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used

# Print only warnings and errors during test
# In test we don't send emails
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :logger, level: :warning

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :micelio, Micelio.GRPC, enabled: false
config :micelio, Micelio.Mailer, adapter: Swoosh.Adapters.Test
config :micelio, Micelio.Mic.RollupScheduler, enabled: false

config :micelio, Micelio.Repo,
  database: Path.join([System.tmp_dir!(), "micelio", "micelio_test#{test_partition}.sqlite3"]),
  journal_mode: :wal,
  synchronous: :normal,
  busy_timeout: 60_000,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :micelio, Micelio.Theme,
  storage: Micelio.Theme.Storage.Local,
  generator: Micelio.Theme.Generator.Static,
  prefix: "themes/daily",
  local_path: Path.join([System.tmp_dir!(), "micelio", "themes_test"])

config :micelio, MicelioWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7CasJHWDMv4jqFHNq+m+JV10UTi5t6g4FH0RJBPjOPwTEbBg2vI/VDZknktJ4B4/",
  server: false

config :micelio, :admin_emails, ["admin@example.com"]

config :micelio, :github_oauth,
  client_id: "github-client-id",
  client_secret: "github-client-secret",
  redirect_uri: "http://localhost:4002/auth/github/callback",
  http_client: Micelio.Auth.GitHubClientStub

config :micelio, :gitlab_oauth,
  client_id: "gitlab-client-id",
  client_secret: "gitlab-client-secret",
  redirect_uri: "http://localhost:4002/auth/gitlab/callback",
  http_client: Micelio.Auth.GitLabClientStub

config :micelio, :notifications_async, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
