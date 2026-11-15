defmodule AuthxDemo.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AuthxDemoWeb.Telemetry,
      AuthxDemo.Repo,
      {AshAuthentication.Supervisor, [otp_app: :authx_demo]},
      {DNSCluster, query: Application.get_env(:authx_demo, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AuthxDemo.PubSub},
      # Start a worker by calling: AuthxDemo.Worker.start_link(arg)
      # {AuthxDemo.Worker, arg},
      # Start to serve requests, typically the last entry
      AuthxDemoWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: AuthxDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AuthxDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
