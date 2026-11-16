defmodule Authx.Repo.Migrations.AddClientDeveloperOwner do
  @moduledoc """
  Adds the owning developer to OAuth clients.

  A client is created by an acting developer and always has exactly one owner,
  so the column is `null: false`: the resource action never accepts an owner
  from input and never produces an unowned row.
  """

  use Ecto.Migration

  def up do
    alter table(:oauth_clients) do
      add :developer_id,
          references(:developers,
            column: :id,
            name: "oauth_clients_developer_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end
  end

  def down do
    drop constraint(:oauth_clients, "oauth_clients_developer_id_fkey")

    alter table(:oauth_clients) do
      remove :developer_id
    end
  end
end
