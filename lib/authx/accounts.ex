defmodule Authx.Accounts do
  use Ash.Domain, otp_app: :authx, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Authx.Accounts.User
    resource Authx.Accounts.Token
  end

  @doc """
  Fetches a user by email.

  Returns `{:ok, user}`, `{:error, :not_found}` when no user exists, or
  `{:error, error}` for other failures. This is an internal lookup for
  operational entry points that need to resolve an actor before running a
  policy-checked action; it bypasses read policies.
  """
  def fetch_user_by_email(email) when is_binary(email) do
    Authx.Accounts.User
    |> Ash.Query.for_read(:get_by_email, %{email: String.trim(email)})
    |> Ash.read_one(domain: __MODULE__, authorize?: false)
    |> case do
      {:ok, nil} -> {:error, :not_found}
      result -> result
    end
  end

  def fetch_admin_by_email(email) when is_binary(email) do
    with {:ok, user} <- fetch_user_by_email(email) do
      case user do
        %Authx.Accounts.User{role: :admin} = admin -> {:ok, admin}
        %Authx.Accounts.User{} -> {:error, :not_admin}
      end
    end
  end

  def get_admin_by_email!(email) when is_binary(email) do
    case fetch_admin_by_email(email) do
      {:ok, admin} -> admin
      {:error, :not_found} -> raise "admin not found for email #{email}"
      {:error, :not_admin} -> raise "user is not an admin for email #{email}"
      {:error, error} -> raise "error fetching admin: #{inspect(error)}"
    end
  end
end
