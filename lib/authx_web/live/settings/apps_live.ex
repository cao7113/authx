defmodule AuthxWeb.Settings.AppsLive do
  @moduledoc """
  Lists the OIDC clients the signed-in user has authorized and lets the user
  revoke a single consent.

  Revoking removes the consent record: the next authorization request for that
  client asks for consent again. It does not sign the user out of Authx or the
  client application, and it does not invalidate already issued tokens.
  """

  use AuthxWeb, :live_view

  alias Authx.Oauth.Consents
  alias Authx.Oauth.Resources.Client

  @impl true
  def mount(_params, _session, socket) do
    consents = Consents.list_for_user(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "已授权应用")
     |> assign(:pending_revoke, nil)
     |> assign(:empty?, consents == [])
     |> stream(:consents, consents)}
  end

  @impl true
  def handle_event("select_revoke", %{"id" => consent_id}, socket) do
    case Consents.fetch_for_user(socket.assigns.current_user, consent_id) do
      {:ok, consent} ->
        {:noreply, assign(socket, :pending_revoke, consent)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:pending_revoke, nil)
         |> put_flash(:error, "这条授权记录不存在或已被撤销。")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "无法读取这条授权记录，请稍后再试。")}
    end
  end

  def handle_event("revoke", _params, %{assigns: %{pending_revoke: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "没有待撤销的授权，请重新选择。")}
  end

  def handle_event("revoke", _params, socket) do
    user = socket.assigns.current_user
    consent = socket.assigns.pending_revoke

    case Consents.revoke(user, consent) do
      {:ok, revoked} ->
        {:noreply,
         socket
         |> assign(:pending_revoke, nil)
         |> reload_stream()
         |> put_flash(:info, "已撤销对 #{client_name(revoked)} 的授权。")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:pending_revoke, nil)
         |> put_flash(:error, "这条授权记录已被撤销，列表已刷新。")
         |> reload_stream()}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "撤销失败，请稍后再试。")}
    end
  end

  def handle_event("cancel_revoke", _params, socket) do
    {:noreply, assign(socket, :pending_revoke, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div
        id="applications-page"
        class="min-h-[calc(100vh-4.5rem)] bg-[#fafbf8] px-5 py-12 sm:px-8 lg:px-12"
      >
        <div class="mx-auto max-w-3xl">
          <header class="max-w-2xl">
            <p class="text-xs font-semibold tracking-[0.14em] text-[#659776] uppercase">
              账号设置
            </p>
            <h1 class="mt-3 text-3xl font-semibold tracking-[-0.04em] text-[#18271f] sm:text-4xl">
              已授权应用
            </h1>
            <p class="mt-4 text-sm leading-7 text-[#68766b]">
              这些应用可以使用 Authx 登录，并读取你允许的信息。撤销后，应用下次登录需要重新获得你的授权。
            </p>
            <p class="mt-2 text-sm leading-7 text-[#8a988d]">
              撤销授权不会退出你在 Authx 或这些应用中的登录，已签发的访问令牌也会在过期前继续有效。
            </p>
          </header>

          <div
            :if={@empty?}
            id="no-consents"
            class="mt-9 rounded-2xl border border-dashed border-[#d6dfd5] bg-white/60 px-6 py-12 text-center"
          >
            <.icon name="hero-shield-check" class="mx-auto size-8 text-[#9bb49f]" />
            <p class="mt-4 text-sm font-semibold text-[#415348]">还没有授权的应用</p>
            <p class="mt-1 text-sm text-[#8a988d]">
              使用 Authx 登录过的应用会显示在这里。
            </p>
          </div>

          <div id="consents" phx-update="stream" class="mt-9 space-y-3">
            <article
              :for={{dom_id, consent} <- @streams.consents}
              id={dom_id}
              class="group rounded-2xl border border-[#e1e8de] bg-white p-5 shadow-[0_12px_40px_-32px_rgba(29,73,54,0.35)] transition-colors hover:border-[#c9d9c6] sm:p-6"
            >
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="min-w-0">
                  <h2 class="truncate text-base font-semibold text-[#18271f]">
                    {client_name(consent)}
                  </h2>
                  <p class="mt-1 text-xs text-[#8a988d]">
                    授权时间 {format_datetime(consent.granted_at)}
                  </p>
                </div>
                <button
                  id={"revoke-consent-#{consent.id}"}
                  type="button"
                  phx-click="select_revoke"
                  phx-value-id={consent.id}
                  class="shrink-0 rounded-full border border-[#d6dfd5] px-4 py-2 text-sm font-semibold text-[#415348] transition-colors hover:border-[#b9cbb6] hover:bg-[#eff5ed] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#3a7053]"
                >
                  撤销授权
                </button>
              </div>

              <dl class="mt-5 grid gap-4 sm:grid-cols-2">
                <div>
                  <dt class="text-[11px] font-semibold tracking-[0.08em] text-[#8a988d] uppercase">
                    可访问的信息
                  </dt>
                  <dd class="mt-1.5 text-sm text-[#415348]">
                    {consent.scope}
                  </dd>
                </div>
                <div>
                  <dt class="text-[11px] font-semibold tracking-[0.08em] text-[#8a988d] uppercase">
                    应用最近活动
                  </dt>
                  <dd class="mt-1.5 text-sm text-[#415348]">
                    {format_last_used(consent)}
                  </dd>
                </div>
              </dl>
            </article>
          </div>
        </div>
      </div>

      <div
        :if={@pending_revoke}
        id="revoke-dialog"
        class="fixed inset-0 z-50 flex items-end justify-center bg-[#18271f]/45 p-4 sm:items-center"
        role="dialog"
        aria-modal="true"
        aria-labelledby="revoke-dialog-title"
      >
        <div class="w-full max-w-md rounded-2xl bg-white p-6 shadow-xl shadow-[#18271f]/20">
          <h2 id="revoke-dialog-title" class="text-lg font-semibold text-[#18271f]">
            撤销对 {client_name(@pending_revoke)} 的授权？
          </h2>
          <p class="mt-3 text-sm leading-6 text-[#68766b]">
            该应用将无法自动使用你的 Authx 登录。下次登录时需要重新同意授权。
          </p>
          <ul class="mt-3 space-y-1.5 text-sm leading-6 text-[#68766b]">
            <li class="flex gap-2">
              <.icon name="hero-check" class="mt-1 size-4 shrink-0 text-[#659776]" /> 不会退出你在该应用中的登录
            </li>
            <li class="flex gap-2">
              <.icon name="hero-check" class="mt-1 size-4 shrink-0 text-[#659776]" />
              已签发的访问令牌会在过期前继续有效
            </li>
          </ul>
          <div class="mt-6 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
            <button
              id="revoke-cancel"
              type="button"
              phx-click="cancel_revoke"
              class="rounded-full border border-[#d6dfd5] px-4 py-2.5 text-sm font-semibold text-[#415348] transition-colors hover:bg-[#eff5ed] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#3a7053]"
            >
              取消
            </button>
            <button
              id="revoke-confirm"
              type="button"
              phx-click="revoke"
              class="rounded-full bg-[#1d4936] px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-[#2f6048] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#3a7053]"
            >
              撤销授权
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp reload_stream(socket) do
    consents = Consents.list_for_user(socket.assigns.current_user)
    socket |> assign(:empty?, consents == []) |> stream(:consents, consents, reset: true)
  end

  defp client_name(%{client: %Client{client_name: name}}) when is_binary(name) and name != "",
    do: name

  defp client_name(_consent), do: "未命名应用"

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M") <> " UTC"
  end

  defp format_datetime(_), do: "未知"

  defp format_last_used(%{client: %Client{last_used_at: %DateTime{} = last_used_at}}) do
    format_datetime(last_used_at)
  end

  defp format_last_used(_consent), do: "暂无记录"
end
