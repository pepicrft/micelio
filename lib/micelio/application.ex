defmodule Micelio.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        MicelioWeb.Telemetry,
        Micelio.Mic.Telemetry,
        Micelio.Repo,
        Micelio.Abuse.Blocklist,
        Micelio.Theme.Server,
        {Task.Supervisor, name: Micelio.Projects.ImportSupervisor},
        {Task.Supervisor, name: Micelio.Webhooks.Supervisor},
        {Task.Supervisor, name: Micelio.Notifications.Supervisor},
        {Task.Supervisor, name: Micelio.RemoteExecution.Supervisor},
        {Task.Supervisor, name: Micelio.ValidationEnvironments.Supervisor},
        {Task.Supervisor, name: Micelio.Mic.RollupSupervisor},
        Micelio.Mic.RollupScheduler,
        {DNSCluster, query: Application.get_env(:micelio, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Micelio.PubSub},
        # Start a worker by calling: Micelio.Worker.start_link(arg)
        # {Micelio.Worker, arg},
        # Start to serve requests, typically the last entry
        MicelioWeb.Endpoint
      ]
      |> maybe_add_grpc_server()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Micelio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MicelioWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_add_grpc_server(children) do
    grpc_config = Application.get_env(:micelio, Micelio.GRPC, [])

    if Keyword.get(grpc_config, :enabled, false) do
      port = Keyword.get(grpc_config, :port, 50_051)
      tls = Keyword.get(grpc_config, :tls, [])
      tls_mode = Keyword.get(grpc_config, :tls_mode, :required)

      if tls == [] and tls_mode == :required do
        raise """
        Micelio.GRPC is enabled but TLS is not configured.
        Configure MICELIO_GRPC_TLS_CERTFILE and MICELIO_GRPC_TLS_KEYFILE.
        """
      end

      adapter_opts =
        case tls do
          [] ->
            [status_handler: {"/up", Micelio.GRPC.StatusHandler, []}]

          _ ->
            [
              cred: GRPC.Credential.new(ssl: tls),
              status_handler: {"/up", Micelio.GRPC.StatusHandler, []}
            ]
        end

      children ++
        [
          {GRPC.Server.Supervisor,
           [
             port: port,
             endpoint: Micelio.GRPC.Endpoint,
             adapter_opts: adapter_opts,
             start_server: true
           ]}
        ]
    else
      children
    end
  end
end
