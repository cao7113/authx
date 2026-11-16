defmodule Authx.Oauth.Validations.RedirectUris do
  @moduledoc """
  Validates a client's registered redirect URIs.

  Every entry must be an absolute HTTPS URL with a host, or HTTP on a loopback
  host for local development. Fragments are never allowed: the authorization
  request compares the redirect URI exactly, and a fragment cannot be sent to
  the server. This runs on the resource action, so the developer console, mix
  tasks and any future API all enforce the same rule.

  A missing value is left to the attribute's own `allow_nil?` validation.
  """

  use Ash.Resource.Validation

  @loopback_hosts ["localhost", "127.0.0.1", "::1"]

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :redirect_uris) do
      nil ->
        :ok

      [] ->
        {:error, field: :redirect_uris, message: "redirect_uris must not be empty"}

      uris when is_list(uris) ->
        if Enum.all?(uris, &valid_uri?/1) do
          :ok
        else
          {:error,
           field: :redirect_uris,
           message:
             "redirect URIs must be https URLs (or http on localhost/127.0.0.1/::1) " <>
               "with a host and no fragment"}
        end

      _ ->
        {:error, field: :redirect_uris, message: "redirect_uris must be a list of URIs"}
    end
  end

  defp valid_uri?(uri) when is_binary(uri) do
    case URI.new(uri) do
      {:ok, %URI{scheme: "https", host: host, fragment: nil}} ->
        is_binary(host) and host != ""

      {:ok, %URI{scheme: "http", host: host, fragment: nil}} ->
        host in @loopback_hosts

      _ ->
        false
    end
  end

  defp valid_uri?(_), do: false
end
