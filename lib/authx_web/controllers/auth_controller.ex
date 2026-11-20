defmodule AuthxWeb.AuthController do
  use AuthxWeb, :controller
  use AshAuthentication.Phoenix.Controller

  require Logger

  alias Authx.Accounts
  alias Authx.Accounts.User

  def success(conn, activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    message =
      case activity do
        {:confirm_new_user, :confirm} -> "Your email address has now been confirmed"
        {:password, :reset} -> "Your password has successfully been reset"
        _ -> "You are now signed in"
      end

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    # If your resource has a different name, update the assign name here (i.e :current_admin)
    |> assign(:current_user, user)
    |> put_flash(:info, message)
    |> redirect(to: return_to)
  end

  def sign_in(conn, _params) do
    render(conn, :sign_in,
      form: Phoenix.Component.to_form(%{}, as: :user),
      magic_form: Phoenix.Component.to_form(%{}, as: :user)
    )
  end

  def register(conn, _params) do
    render(conn, :register, form: Phoenix.Component.to_form(%{}, as: :user))
  end

  def please_confirm(conn, _params) do
    case pending_user(conn) do
      {:ok, %User{confirmed_at: nil} = user} ->
        render(conn, :please_confirm, user: user)

      _ ->
        conn
        |> delete_session(:pending_confirmation)
        |> put_flash(:info, "请先登录或注册后再确认邮箱")
        |> redirect(to: ~p"/sign-in")
    end
  end

  def resend_confirmation(conn, _params) do
    with {:ok, %User{confirmed_at: nil} = user} <- pending_user(conn),
         :ok <- send_confirmation(user) do
      conn
      |> put_flash(:info, "如果账户仍未确认，新的确认邮件已经发送")
      |> redirect(to: ~p"/auth/please-confirm")
    else
      _ ->
        conn
        |> put_flash(:info, "如果账户仍未确认，新的确认邮件已经发送")
        |> redirect(to: ~p"/auth/please-confirm")
    end
  end

  def failure(conn, activity, reason) do
    # Logger.error("## Authentication failure: #{inspect({activity, reason})}")

    case {activity, reason} do
      {_,
       %AshAuthentication.Errors.AuthenticationFailed{
         caused_by: %AshAuthentication.Errors.UnconfirmedUser{}
       }} ->
        conn
        |> put_session(:pending_confirmation, pending_confirmation(conn))
        |> redirect(to: ~p"/auth/please-confirm")

      {_,
       %AshAuthentication.Errors.AuthenticationFailed{
         caused_by: %Ash.Error.Forbidden{
           errors: [%AshAuthentication.Errors.CannotConfirmUnconfirmedUser{}]
         }
       }} ->
        failure_redirect(conn, """
        You have already signed in another way, but have not confirmed your account.
        You can confirm your account using the link we sent to you, or by resetting your password.
        """)

      {_,
       %AshAuthentication.Errors.AuthenticationFailed{
         caused_by: %AshAuthentication.Errors.ConfirmationRequired{}
       }} ->
        failure_redirect(conn, """
        An account with this email already exists. We've sent a link to that
        address - confirm it to finish linking this provider to your account.
        """)

      _ ->
        failure_redirect(conn, "Incorrect email or password")
    end
  end

  defp failure_redirect(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/sign-in")
  end

  defp pending_confirmation(conn) do
    case conn.params do
      %{"user" => %{"email" => email}} when is_binary(email) ->
        case Accounts.fetch_user_by_email(email) do
          {:ok, %User{id: id} = user} ->
            %{user_id: id, email: to_string(user.email), created_at: System.system_time(:second)}

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp pending_user(conn) do
    case get_session(conn, :pending_confirmation) do
      %{"user_id" => user_id} -> fetch_user(user_id)
      %{user_id: user_id} -> fetch_user(user_id)
      _ -> {:error, :missing_pending_confirmation}
    end
  end

  defp fetch_user(user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, id} -> Ash.get(User, id, domain: Accounts, authorize?: false)
      :error -> {:error, :invalid_user_id}
    end
  end

  defp send_confirmation(user) do
    strategy = AshAuthentication.Info.strategy!(User, :confirm_new_user)
    changeset = Ash.Changeset.new(user)

    with {:ok, token} <-
           AshAuthentication.AddOn.Confirmation.confirmation_token(
             strategy,
             changeset,
             user,
             domain: Accounts
           ),
         :ok <-
           Authx.Accounts.User.Senders.SendNewUserConfirmationEmail.send(
             user,
             token,
             []
           ) do
      :ok
    end
  end

  def sign_out(conn, _params) do
    return_to = get_session(conn, :return_to) || ~p"/"

    if user = conn.assigns[:current_user] do
      :ok =
        Phoenix.PubSub.broadcast(
          Authx.PubSub,
          Authx.Accounts.Admins.access_topic(user.id),
          :admin_access_revoked
        )
    end

    conn
    |> clear_session(:authx)
    |> put_flash(:info, "You are now signed out")
    |> redirect(to: return_to)
  end
end
