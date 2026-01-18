# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure Boruta schemas to use custom table names
config :boruta, Boruta.Ecto.Token, source: "oauth_tokens"

config :boruta, Boruta.Oauth,
  repo: Micelio.Repo,
  contexts: [
    resource_owners: Micelio.OAuth.ResourceOwners,
    clients: Micelio.OAuth.Clients,
    access_tokens: Micelio.OAuth.AccessTokens
  ],
  token_generator: Micelio.OAuth.TokenGenerator

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  micelio: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Hammer rate limiting configuration
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :mime, :types, %{
  "application/activity+json" => ["activity+json"],
  "application/jrd+json" => ["jrd+json"]
}

config :micelio, Micelio.GRPC,
  enabled: false,
  port: 50_051,
  require_auth_token: false

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :micelio, Micelio.Mailer, adapter: Swoosh.Adapters.Local

# Configure the endpoint
config :micelio, MicelioWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MicelioWeb.ErrorHTML, json: MicelioWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Micelio.PubSub,
  live_view: [signing_salt: "uBaIW6yU"]

config :micelio,
  ecto_repos: [Micelio.Repo],
  # Import environment specific config. This must remain at the bottom
  generators: [timestamp_type: :utc_datetime]

# Use Jason for JSON parsing in Phoenix
# of this file so it overrides the configuration defined above.
config :phoenix, :json_library, JSON

import_config "#{config_env()}.exs"
