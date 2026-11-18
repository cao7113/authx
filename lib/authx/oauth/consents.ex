defmodule Authx.Oauth.Consents do
  @moduledoc """
  User-facing OIDC consent operations.

  A consent records that a signed-in user allowed a client to use a set of
  scopes. Revoking it removes that record so the next authorization request
  asks for consent again. Revoking does not end any Authx or client session
  and does not invalidate already issued access tokens.

  Only the consent's owning user may list or revoke it; ownership always comes
  from the authenticated actor, never from input.
  """

  require Ash.Query

  alias Authx.Accounts.User
  alias Authx.Audit
  alias Authx.Oauth.Resources.Client
  alias Authx.Oauth.Resources.Consent

  @doc """
  Lists the user's consents, newest first, with the client preloaded.
  """
  def list_for_user(%User{id: user_id} = user) do
    Consent
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.load(:client)
    |> Ash.Query.sort(granted_at: :desc)
    |> Ash.read!(actor: user)
  end

  @doc """
  Fetches one of the user's consents by id, or returns `{:error, :not_found}`.

  The query is scoped to the acting user so ids belonging to someone else are
  indistinguishable from ids that do not exist.
  """
  def fetch_for_user(%User{} = user, consent_id) when is_binary(consent_id) do
    case Ecto.UUID.cast(consent_id) do
      {:ok, uuid} ->
        Consent
        |> Ash.Query.filter(id == ^uuid and user_id == ^user.id)
        |> Ash.Query.load(:client)
        |> Ash.read_one(actor: user)
        |> case do
          {:ok, nil} -> {:error, :not_found}
          {:ok, consent} -> {:ok, consent}
          {:error, error} -> {:error, error}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Revokes a consent and records a `consent.revoked` audit event atomically.

  Returns `{:ok, revoked_consent}` or an error. If the consent was already
  removed, the destroy action reports not found and no audit event is written.
  """
  def revoke(%User{} = user, %Consent{id: consent_id}) do
    with {:ok, consent} <- fetch_for_user(user, consent_id) do
      Consent
      |> Ash.transact(fn ->
        with {:ok, client} <- fetch_consent_client(user, consent),
             {:ok, revoked} <-
               Ash.destroy(consent, actor: user, return_destroyed?: true),
             {:ok, _event} <- Audit.record(revocation_event(user, consent, client)) do
          revoked
        end
      end)
    end
  end

  defp fetch_consent_client(_user, %Consent{client: %Client{} = client}), do: {:ok, client}

  defp fetch_consent_client(%User{} = user, %Consent{client_id: client_id}) do
    case Ash.get(Client, client_id, actor: user) do
      {:ok, nil} -> {:ok, nil}
      {:ok, client} -> {:ok, client}
      {:error, error} -> {:error, error}
    end
  end

  defp revocation_event(user, consent, client) do
    %{
      event: "consent.revoked",
      actor_user_id: user.id,
      subject_user_id: user.id,
      target_type: "oauth_client",
      target_id: consent.client_id,
      metadata: %{
        "client_name" => client && client.client_name,
        "scope" => consent.scope
      }
    }
  end
end
