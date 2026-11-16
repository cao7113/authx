defmodule Authx.Oauth.Oidc.KeysTest do
  use ExUnit.Case, async: false

  alias Authx.Oauth.Oidc.Keys

  @tag :tmp_dir
  test "a configured private key keeps tokens verifiable across restarts", %{tmp_dir: dir} do
    path = Path.join(dir, "oidc.pem")
    key = JOSE.JWK.generate_key({:rsa, 2048})
    {_, pem} = JOSE.JWK.to_pem(key)
    File.write!(path, pem)

    previous = Application.get_env(:authx, :oidc_private_key_file)
    Application.put_env(:authx, :oidc_private_key_file, path)

    on_exit(fn ->
      if previous do
        Application.put_env(:authx, :oidc_private_key_file, previous)
      else
        Application.delete_env(:authx, :oidc_private_key_file)
      end
    end)

    assert {:ok, first} = Keys.init(nil)
    assert {:reply, token, _} = Keys.handle_call({:sign, %{"sub" => "user"}}, self(), first)
    assert {:ok, restarted} = Keys.init(nil)
    assert {:reply, public, _} = Keys.handle_call(:public_key, self(), restarted)
    assert {true, _, _} = JOSE.JWT.verify_strict(JOSE.JWK.from_map(public), ["RS256"], token)
  end
end
