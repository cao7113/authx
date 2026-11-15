defmodule AuthxDemo.Accounts.OidcUserTest do
  use AuthxDemo.DataCase, async: false

  alias AuthxDemo.Accounts.User

  test "repeated authentication uses issuer and subject and updates email" do
    first = register("user-one", "first@example.com")
    second = register("user-one", "updated@example.com")
    other = register("user-two", "updated@example.com")

    assert first.id == second.id
    assert second.subject == "user-one"
    assert second.issuer == "http://localhost:4000"
    assert second.email == "updated@example.com"
    refute other.id == first.id
  end

  test "the same subject from another issuer is a different user" do
    first = register("same-subject", "one@example.com")
    issuer = Application.fetch_env!(:authx_demo, :oidc_issuer)
    on_exit(fn -> Application.put_env(:authx_demo, :oidc_issuer, issuer) end)
    Application.put_env(:authx_demo, :oidc_issuer, "https://other.example")

    second = register("same-subject", "two@example.com")
    refute first.id == second.id
    assert second.issuer == "https://other.example"
  end

  defp register(subject, email) do
    User
    |> Ash.Changeset.for_create(:register_with_authx, %{
      user_info: %{"sub" => subject, "email" => email},
      oauth_tokens: %{"access_token" => "test-access-token"}
    })
    |> Ash.create!()
  end
end
