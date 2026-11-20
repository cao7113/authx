defmodule AuthxWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AuthxWeb, :html

  @dev_routes Application.compile_env(:authx, :dev_routes, false)

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <main>
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc "Renders the shared site navigation."
  attr :current_user, :any, default: nil
  attr :dev_routes_enabled, :boolean, default: @dev_routes

  def site_header(assigns) do
    assigns =
      assign(
        assigns,
        :admin?,
        assigns.current_user && Authx.Accounts.Admins.admin?(assigns.current_user.id)
      )

    ~H"""
    <header id="site-header" class="border-b border-[#e5e9e3] bg-[#fafbf8] text-[#18271f]">
      <nav
        aria-label="主导航"
        class="mx-auto flex min-h-18 max-w-7xl flex-wrap items-center justify-between gap-x-4 gap-y-2 px-5 py-3 sm:px-8 lg:px-12"
      >
        <.link
          href={~p"/"}
          id="site-home-link"
          class="group inline-flex shrink-0 items-center gap-2.5 rounded-md focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#3a7053]"
        >
          <span class="flex size-9 items-center justify-center rounded-xl bg-[#1d4936] text-[#e2f5bf] transition-transform group-hover:rotate-6">
            <.icon name="hero-key-solid" class="size-5" />
          </span>
          <span class="text-[1.15rem] font-bold tracking-[-0.06em]">authx<span class="text-[#659776]">.</span></span>
        </.link>

        <div class="hidden items-center gap-8 text-sm font-medium text-[#68766b] sm:flex">
          <.link href={~p"/"} class="transition-colors hover:text-[#173b2a]">首页</.link>
          <.link href="/#about" class="transition-colors hover:text-[#173b2a]">关于 Authx</.link>
        </div>

        <div class="flex flex-wrap items-center gap-2 sm:gap-3">
          <div id="tools" class="nav-tools group relative">
            <button
              id="tools-toggle"
              type="button"
              aria-expanded="false"
              aria-controls="dev-tools-menu"
              class="flex cursor-pointer items-center gap-1 rounded-md px-2 py-2 text-sm font-semibold text-[#68766b] transition-colors hover:text-[#173b2a] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#3a7053]"
            >
              Tools <.icon name="hero-chevron-down" class="size-4" />
            </button>
            <div
              id="tools-menu"
              class="nav-tools-menu absolute top-full right-0 z-50 hidden w-48 pt-2"
            >
              <div class="rounded-xl border border-[#dfe8db] bg-white p-1.5 shadow-lg shadow-[#1d4936]/10">
                <a
                  href="/dev/mailbox"
                  target="_blank"
                  class="block rounded-lg px-3 py-2 text-sm text-[#415348] transition-colors hover:bg-[#eff5ed]"
                >
                  Mailbox
                </a>
              </div>
            </div>
          </div>
          <%= if @current_user do %>
            <div id="user-menu" class="nav-tools group relative">
              <button
                id="user-menu-toggle"
                type="button"
                aria-expanded="false"
                aria-controls="user-menu-options"
                class="flex max-w-[min(70vw,20rem)] cursor-pointer items-center gap-2 rounded-full border border-[#d6dfd5] px-3 py-2 text-sm font-semibold text-[#415348] transition-colors hover:border-[#1d4936] hover:bg-[#eff5ed] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#3a7053]"
              >
                <.icon name="hero-user-circle" class="size-5 shrink-0 text-[#659776]" />
                <span id="nav-user-email" class="truncate">{to_string(@current_user.email)}</span>
                <span
                  :if={@current_user.role != :user}
                  id="nav-user-role"
                  class="shrink-0 text-[#659776]"
                >
                  ({@current_user.role})
                </span>
                <.icon name="hero-chevron-down" class="size-4 shrink-0" />
              </button>
              <div
                id="user-menu-options"
                class="nav-tools-menu absolute top-full right-0 z-50 hidden w-48 pt-2"
              >
                <div class="rounded-xl border border-[#dfe8db] bg-white p-1.5 shadow-lg shadow-[#1d4936]/10">
                  <.link
                    href={~p"/settings/apps"}
                    id="nav-authorized-apps"
                    class="block rounded-lg px-3 py-2 text-sm text-[#415348] transition-colors hover:bg-[#eff5ed]"
                  >
                    已授权应用
                  </.link>
                  <.link
                    href={~p"/sign-out"}
                    id="nav-sign-out"
                    class="block rounded-lg px-3 py-2 text-sm text-[#415348] transition-colors hover:bg-[#eff5ed]"
                  >
                    退出登录
                  </.link>
                </div>
              </div>
            </div>
          <% else %>
            <.link
              href={~p"/sign-in"}
              id="nav-sign-in"
              class="rounded-full px-3 py-2 text-sm font-semibold text-[#415348] transition-colors hover:text-[#173b2a] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#3a7053]"
            >
              登录
            </.link>
            <.link
              href={~p"/register"}
              id="nav-register"
              class="rounded-full bg-[#1d4936] px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-[#2f6048] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#3a7053]"
            >
              创建账号
            </.link>
          <% end %>
          <div :if={@admin?} id="admin-tools" class="nav-tools group relative">
            <button
              id="admin-tools-toggle"
              type="button"
              aria-expanded="false"
              aria-controls="admin-tools-menu"
              class="flex cursor-pointer items-center gap-1 rounded-md px-2 py-2 text-sm font-semibold text-[#68766b] transition-colors hover:text-[#173b2a] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#3a7053]"
            >
              Admin <.icon name="hero-chevron-down" class="size-4" />
            </button>
            <div
              id="admin-tools-menu"
              class="nav-tools-menu absolute top-full right-0 z-50 hidden w-48 pt-2"
            >
              <div class="rounded-xl border border-[#dfe8db] bg-white p-1.5 shadow-lg shadow-[#1d4936]/10">
                <.link
                  id="admin-dashboard-link"
                  href="/admin"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="block rounded-lg px-3 py-2 text-sm text-[#415348] transition-colors hover:bg-[#eff5ed]"
                >
                  Ash Admin
                </.link>
                <.link
                  id="live-dashboard-link"
                  href={~p"/admin/dashboard"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="block rounded-lg px-3 py-2 text-sm text-[#415348] transition-colors hover:bg-[#eff5ed]"
                >
                  Live Dashboard
                </.link>
                <.link
                  id="oban-dashboard-link"
                  href="/oban"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="block rounded-lg px-3 py-2 text-sm text-[#415348] transition-colors hover:bg-[#eff5ed]"
                >
                  Oban
                </.link>
              </div>
            </div>
          </div>
        </div>
      </nav>
    </header>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
