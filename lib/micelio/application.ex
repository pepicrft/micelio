defmodule Micelio.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MicelioWeb.Telemetry,
      Micelio.Repo,
      {DNSCluster, query: Application.get_env(:micelio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Micelio.PubSub},
      # Start a worker by calling: Micelio.Worker.start_link(arg)
      # {Micelio.Worker, arg},
      # Start to serve requests, typically the last entry
      MicelioWeb.Endpoint
    ]

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
end
