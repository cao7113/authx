defmodule AuthxDemo.Repo do
  use AshPostgres.Repo, otp_app: :authx_demo

  @impl true
  def installed_extensions, do: ["ash-functions"]

  @impl true
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
end
