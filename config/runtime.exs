import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/micelio start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :micelio, MicelioWeb.Endpoint, server: true
end

config :micelio, MicelioWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :micelio, Micelio.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  config :micelio, MicelioWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :micelio, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Configure SMTP mailer
  smtp_host = System.get_env("SMTP_HOST")
  smtp_username = System.get_env("SMTP_USERNAME")
  smtp_password = System.get_env("SMTP_PASSWORD")

  required_smtp_vars = [
    {"SMTP_HOST", smtp_host},
    {"SMTP_USERNAME", smtp_username},
    {"SMTP_PASSWORD", smtp_password}
  ]

  missing_smtp_vars = required_smtp_vars |> Enum.filter(fn {_, val} -> is_nil(val) end) |> Enum.map(fn {name, _} -> name end)

  if Enum.any?(missing_smtp_vars) do
    raise """
    Missing required SMTP configuration. The following environment variables are not set:

    #{Enum.map(missing_smtp_vars, &"  - #{&1}") |> Enum.join("\n")}

    Please configure SMTP using fnox:
      fnox set SMTP_HOST smtp.example.com
      fnox set SMTP_USERNAME your-username
      fnox set SMTP_PASSWORD your-password
      fnox set SMTP_PORT 587
      fnox set SMTP_FROM_EMAIL noreply@yourapp.com
      fnox set SMTP_FROM_NAME "Your App"

    Optional variables (have defaults):
      - SMTP_PORT (default: "587")
      - SMTP_FROM_EMAIL (default: "noreply@micelio.dev")
      - SMTP_FROM_NAME (default: "Micelio")
    """
  end

  smtp_port = System.get_env("SMTP_PORT") || "587"
  smtp_from_email = System.get_env("SMTP_FROM_EMAIL") || "noreply@micelio.dev"
  smtp_from_name = System.get_env("SMTP_FROM_NAME") || "Micelio"

  config :micelio, Micelio.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_host,
    port: String.to_integer(smtp_port),
    username: smtp_username,
    password: smtp_password,
    tls: :if_available,
    ssl: false,
    auth: :always,
    from: {smtp_from_name, smtp_from_email}

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :micelio, MicelioWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :micelio, MicelioWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :micelio, Micelio.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
