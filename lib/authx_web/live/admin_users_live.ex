defmodule AuthxWeb.AdminUsersLive do
  use AuthxWeb, :live_view

  require Logger

  alias Authx.Accounts.Admins

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "用户管理",
       form: to_form(%{"email" => ""}, as: :search),
       selected_user: nil
     )}
  end

  @impl true
  def handle_event("search", %{"search" => %{"email" => email}}, socket) do
    email = String.trim(email)

    case Admins.find_by_email(socket.assigns.current_user, email) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(form: to_form(%{"email" => email}, as: :search), selected_user: user)
         |> maybe_not_found(user)}

      {:error, %Ash.Error.Forbidden{}} ->
        {:noreply, redirect(socket, to: ~p"/")}

      {:error, error} ->
        Logger.error("Failed to search for user: #{inspect(error)}")
        {:noreply, put_flash(socket, :error, "无法查询用户，请稍后重试。")}
    end
  end

  def handle_event("set-role", %{"id" => id, "role" => role}, socket)
      when role in ["admin", "user"] do
    role = if role == "admin", do: :admin, else: :user

    case Admins.set_role(socket.assigns.current_user.id, id, role) do
      {:ok, user} ->
        {:noreply, socket |> assign(selected_user: user) |> put_flash(:info, "用户角色已更新。")}

      {:error, :forbidden} ->
        {:noreply, redirect(socket, to: ~p"/")}

      {:error, :last_admin} ->
        {:noreply, put_flash(socket, :error, "不能移除最后一位管理员。")}

      {:error, reason} ->
        Logger.error("Failed to change administrator role: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "无法更新用户角色，请稍后重试。")}
    end
  end

  defp maybe_not_found(socket, nil), do: put_flash(socket, :error, "未找到用户。")
  defp maybe_not_found(socket, _user), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mx-auto max-w-2xl px-5 py-16 sm:px-8">
        <p class="text-xs font-semibold tracking-[0.16em] text-[#719576]">ADMINISTRATION</p>
        <h1 class="mt-3 text-3xl font-semibold tracking-tight text-[#18271f]">用户管理</h1>
        <p class="mt-3 text-sm leading-6 text-[#68766b]">通过邮箱查找已注册用户，并管理管理员权限。</p>

        <.form for={@form} id="admin-user-search" phx-submit="search" class="mt-8 space-y-4">
          <.input field={@form[:email]} type="email" label="邮箱" required />
          <button
            type="submit"
            class="rounded-full bg-[#1d4936] px-5 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-[#2f6048]"
          >
            查找用户
          </button>
        </.form>
        <div
          :if={@selected_user}
          id="admin-selected-user"
          class="mt-8 rounded-2xl border border-[#dfe8db] bg-white p-6"
        >
          <p class="font-semibold text-[#18271f]">{@selected_user.email}</p>
          <p class="mt-2 text-sm text-[#68766b]">角色：{@selected_user.role}</p>
          <button
            id="admin-toggle-role"
            type="button"
            phx-click="set-role"
            phx-value-id={@selected_user.id}
            phx-value-role={if @selected_user.role == :admin, do: "user", else: "admin"}
            data-confirm="确定更改此用户的管理员权限吗？"
            class="mt-5 rounded-full border border-[#cbd9cb] px-4 py-2 text-sm font-semibold text-[#1d4936] transition-colors hover:bg-[#eff5ed]"
          >
            {if @selected_user.role == :admin, do: "移除管理员", else: "设为管理员"}
          </button>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
