# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  micelio: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

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
  generators: [timestamp_type: :utc_datetime]

# Import environment specific config. This must remain at the bottom

# Use Jason for JSON parsing in Phoenix
# of this file so it overrides the configuration defined above.
config :phoenix, :json_library, JSON

import_config "#{config_env()}.exs"
