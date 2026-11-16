defmodule Authx.Developers.Checks.ActiveDeveloper do
  @moduledoc """
  Authorizes developer-facing actions.

  The actor must be an `Authx.Developers.Developer` whose record is still
  active. The status is re-read from the database, so an actor that was
  captured before a developer was suspended cannot keep acting on the
  strength of a stale struct.
  """

  use Ash.Policy.SimpleCheck

  alias Authx.Developers.Developer

  @impl true
  def describe(_opts), do: "the actor is a current active developer"

  @impl true
  def match?(%Developer{} = developer, _context, _opts),
    do: Authx.Developers.active_developer?(developer)

  def match?(_, _, _), do: false
end
