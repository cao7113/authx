defmodule Authx.Accounts.Checks.AdminCheck do
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "the actor is a current administrator"

  @impl true
  def match?(%Authx.Accounts.User{id: id}, _context, _opts) do
    Authx.Accounts.Admins.admin_status(id)
  end

  def match?(_, _, _), do: false
end
