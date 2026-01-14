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

# Storage configuration (local by default, S3 opt-in)
storage_backend =
  case System.get_env("STORAGE_BACKEND") do
    "s3" -> :s3
    _ -> :local
  end

local_path_default =
  System.get_env("STORAGE_LOCAL_PATH") ||
    case config_env() do
      :prod -> "/var/micelio/storage"
      _ -> Path.join([System.tmp_dir!(), "micelio", "storage"])
    end

storage_config =
  case storage_backend do
    :local ->
      [
        backend: :local,
        local_path: local_path_default
      ]

    :s3 ->
      [
        backend: :s3,
        s3_bucket: System.fetch_env!("S3_BUCKET"),
        s3_region: System.get_env("S3_REGION") || "us-east-1"
        # AWS credentials from IAM roles or environment
      ]
  end

grpc_enabled = System.get_env("MICELIO_GRPC_ENABLED") == "true"
grpc_tls_certfile = System.get_env("MICELIO_GRPC_TLS_CERTFILE")
grpc_tls_keyfile = System.get_env("MICELIO_GRPC_TLS_KEYFILE")
grpc_tls_cacertfile = System.get_env("MICELIO_GRPC_TLS_CACERTFILE")

grpc_tls_mode =
  case System.get_env("MICELIO_GRPC_TLS_MODE") do
    "proxy" -> :proxy
    "insecure" -> :insecure
    _ -> :required
  end

{grpc_tls_certfile, grpc_tls_keyfile} =
  case {grpc_tls_certfile, grpc_tls_keyfile} do
    {nil, nil} ->
      cert_pem = System.get_env("TLS_CERT_PEM")
      key_pem = System.get_env("TLS_KEY_PEM")

      if is_binary(cert_pem) and is_binary(key_pem) do
        tls_dir = Path.join([System.tmp_dir!(), "micelio", "grpc-tls"])
        File.mkdir_p!(tls_dir)

        certfile = Path.join(tls_dir, "cert.pem")
        keyfile = Path.join(tls_dir, "key.pem")

        File.write!(certfile, String.replace(cert_pem, "\\n", "\n"))
        File.write!(keyfile, String.replace(key_pem, "\\n", "\n"))
        File.chmod!(certfile, 0o600)
        File.chmod!(keyfile, 0o600)

        {certfile, keyfile}
      else
        {nil, nil}
      end

    {certfile, keyfile} ->
      {certfile, keyfile}
  end

grpc_tls =
  case {grpc_tls_certfile, grpc_tls_keyfile} do
    {nil, nil} ->
      []

    {certfile, keyfile} ->
      tls_base = [certfile: certfile, keyfile: keyfile]

      case grpc_tls_cacertfile do
        nil -> tls_base
        cacertfile -> tls_base ++ [cacertfile: cacertfile]
      end
  end

config :micelio, Micelio.Storage, storage_config

if grpc_enabled do
  config :micelio, Micelio.GRPC,
    enabled: true,
    port: String.to_integer(System.get_env("MICELIO_GRPC_PORT", "50051")),
    tls_mode: grpc_tls_mode,
    tls: grpc_tls
end

config :micelio, MicelioWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      "/var/micelio/micelio.sqlite3"

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

  # Configure SMTP mailer
  smtp_host = System.get_env("SMTP_HOST")
  smtp_username = System.get_env("SMTP_USERNAME")
  smtp_password = System.get_env("SMTP_PASSWORD")

  required_smtp_vars = [
    {"SMTP_HOST", smtp_host},
    {"SMTP_USERNAME", smtp_username},
    {"SMTP_PASSWORD", smtp_password}
  ]

  missing_smtp_vars =
    required_smtp_vars
    |> Enum.filter(fn {_, val} -> is_nil(val) end)
    |> Enum.map(fn {name, _} -> name end)

  config :micelio, Micelio.Repo,
    database: database_path,
    journal_mode: :wal,
    synchronous: :normal,
    busy_timeout: 5_000,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

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
      - SMTP_SSL (default: "false")
      - SMTP_TLS (default: "if_available")
      - SMTP_FROM_EMAIL (default: "noreply@micelio.dev")
      - SMTP_FROM_NAME (default: "Micelio")
      - SMTP_TLS_VERIFY (default: "true")
      - SMTP_TLS_CA_CERTS_PATH (default: system CA certs)
      - SMTP_TLS_SERVER_NAME (default: SMTP_HOST)
    """
  end

  smtp_port = System.get_env("SMTP_PORT") || "587"
  smtp_from_email = System.get_env("SMTP_FROM_EMAIL") || "noreply@micelio.dev"
  smtp_from_name = System.get_env("SMTP_FROM_NAME") || "Micelio"

  # Parse SSL/TLS settings from environment variables
  smtp_ssl = System.get_env("SMTP_SSL", "false") == "true"

  smtp_tls =
    case System.get_env("SMTP_TLS", "if_available") do
      "true" -> :always
      "always" -> :always
      "if_available" -> :if_available
      "false" -> :never
      "never" -> :never
      _ -> :if_available
    end

  # Configure TLS options for SMTP.
  # Default to peer verification and allow optional CA overrides.
  smtp_tls_verify = System.get_env("SMTP_TLS_VERIFY", "true") != "false"
  smtp_tls_ca_cert_path = System.get_env("SMTP_TLS_CA_CERTS_PATH")
  smtp_tls_server_name = System.get_env("SMTP_TLS_SERVER_NAME") || smtp_host

  smtp_tls_options =
    cond do
      (smtp_ssl or smtp_tls in [:always, :if_available]) and smtp_tls_verify ->
        ca_options =
          case smtp_tls_ca_cert_path do
            nil -> [cacerts: :public_key.cacerts_get()]
            path -> [cacertfile: path]
          end

        [
          verify: :verify_peer,
          depth: 99,
          server_name_indication: String.to_charlist(smtp_tls_server_name)
        ] ++ ca_options

      smtp_ssl or smtp_tls in [:always, :if_available] ->
        [verify: :verify_none]

      true ->
        []
    end

  config :micelio, Micelio.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_host,
    port: String.to_integer(smtp_port),
    username: smtp_username,
    password: smtp_password,
    tls: smtp_tls,
    ssl: smtp_ssl,
    tls_options: smtp_tls_options,
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
