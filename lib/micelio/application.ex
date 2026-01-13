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
        Micelio.Hif.Telemetry,
        Micelio.Hif.RollupScheduler,
        Micelio.Repo,
        {Task.Supervisor, name: Micelio.Hif.RollupSupervisor},
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

      if tls == [] do
        raise """
        Micelio.GRPC is enabled but TLS is not configured.
        Configure MICELIO_GRPC_TLS_CERTFILE and MICELIO_GRPC_TLS_KEYFILE.
        """
      end

      children ++
        [
          {GRPC.Server.Supervisor,
           %{
             port: port,
             servers: [Micelio.GRPC.Endpoint],
             cred: GRPC.Credential.new(ssl: tls)
           }}
        ]
    else
      children
    end
  end
end
