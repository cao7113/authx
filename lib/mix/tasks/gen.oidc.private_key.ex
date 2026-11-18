defmodule Mix.Tasks.Gen.Oidc.PrivateKey do
  use Mix.Task

  @shortdoc "Generates an RSA private key for AUTHX_OIDC_PRIVATE_KEY_FILE"

  @moduledoc """
  Generates an RSA-2048 private key in PEM format for ID Token signing.

      mix gen.oidc.private_key PATH

  The key is written with mode `0600` and an existing file is never
  overwritten. Mount the generated file into the production release and point
  `AUTHX_OIDC_PRIVATE_KEY_FILE` at it. Keep the key stable across restarts:
  replacing it invalidates all previously issued ID Tokens.

  See [OIDC ID Token signing keys](oidc-signing-keys.md) for background.
  """

  @impl Mix.Task
  def run([path]) do
    path = Path.expand(path)

    if File.exists?(path) do
      Mix.raise("refusing to overwrite existing file: #{path}")
    end

    key = JOSE.JWK.generate_key({:rsa, 2048})
    {_fields, pem} = JOSE.JWK.to_pem(key)

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, pem, [:binary])
    File.chmod!(path, 0o600)

    Mix.shell().info("Wrote RSA-2048 private key to #{path}")
    Mix.shell().info("kid=#{JOSE.JWK.thumbprint(key)}")
    Mix.shell().info("Set AUTHX_OIDC_PRIVATE_KEY_FILE=#{path}")
  end

  def run(_args), do: Mix.raise("usage: mix gen.oidc.private_key PATH")
end
