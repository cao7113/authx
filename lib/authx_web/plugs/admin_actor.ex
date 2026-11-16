defmodule AuthxWeb.Plugs.AdminActor do
  # https://ash-admin.hexdocs.pm/getting-started-with-ash-admin.html#security
  # built-in plug https://github.com/ash-project/ash_admin/blob/v1.3.2/lib/ash_admin/actor_plug/plug.ex
  # config :ash_admin, :actor_plug, xxxPlug

  @moduledoc false
  @behaviour AshAdmin.ActorPlug

  @doc false
  @impl true
  def actor_assigns(socket, session) do
    user = socket.assigns[:current_user]

    [
      actor: user,
      actor_domain: Authx.Accounts,
      actor_resources: [{Authx.Accounts, Authx.Accounts.User}],
      actor_paused: false,
      # todo
      # authorizing: true,
      authorizing: false,
      actor_tenant: session["tenant"],
      tenant: session["tenant"]
    ]
  end

  @doc false
  @impl true
  def set_actor_session(conn), do: conn
end
