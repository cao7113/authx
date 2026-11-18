defmodule Mix.Tasks.Gen.Oidc.PrivateKeyTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @tag :tmp_dir
  test "writes an RSA private key PEM with restrictive permissions", %{tmp_dir: dir} do
    path = Path.join(dir, "oidc_private_key.pem")

    capture_io(fn ->
      Mix.Tasks.Gen.Oidc.PrivateKey.run([path])
    end)

    assert File.exists?(path)

    assert {:ok, %File.Stat{mode: mode}} = File.stat(path)
    assert Bitwise.band(mode, 0o777) == 0o600

    pem = File.read!(path)
    assert pem =~ "BEGIN PRIVATE KEY"

    {_, params} = path |> File.read!() |> JOSE.JWK.from_pem() |> JOSE.JWK.to_map()
    assert params["kty"] == "RSA"
    assert is_binary(params["d"])
  end

  @tag :tmp_dir
  test "refuses to overwrite an existing file", %{tmp_dir: dir} do
    path = Path.join(dir, "oidc_private_key.pem")
    File.write!(path, "existing key")

    capture_io(fn ->
      assert_raise Mix.Error, ~r/refusing to overwrite/, fn ->
        Mix.Tasks.Gen.Oidc.PrivateKey.run([path])
      end
    end)
  end

  test "requires a path" do
    assert_raise Mix.Error, ~r/usage: mix gen.oidc.private_key PATH/, fn ->
      Mix.Tasks.Gen.Oidc.PrivateKey.run([])
    end
  end
end
