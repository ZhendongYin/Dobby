defmodule Dobby.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DobbyWeb.Telemetry,
      Dobby.Repo,
      {DNSCluster, query: Application.get_env(:dobby, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Dobby.PubSub},
      # Campaign status scheduler - automatically updates campaign statuses
      Dobby.Campaigns.Scheduler,
      # Start to serve requests, typically the last entry
      DobbyWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dobby.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DobbyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
