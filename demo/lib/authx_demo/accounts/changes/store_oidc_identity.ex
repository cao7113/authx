defmodule AuthxDemo.Accounts.Changes.StoreOidcIdentity do
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    info = Ash.Changeset.get_argument(changeset, :user_info)

  # require Logger
  # Logger.info("#### Storing OIDC identity: #{inspect(info)}")
  # %{"email" => "admin@l.h", "email_verified" => true, "sub" => "29ba64d4-d72c-4b24-a562-caa7c2ea85d5"}

    changeset
    |> Ash.Changeset.change_attribute(:issuer, Application.fetch_env!(:authx_demo, :oidc_issuer))
    |> Ash.Changeset.change_attribute(:subject, info["sub"])
    |> Ash.Changeset.change_attribute(:email, info["email"])
  end
end
