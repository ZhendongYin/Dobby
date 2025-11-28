defmodule DobbyWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DobbyWeb, :html

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
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:scope, assigns.current_scope && assigns.current_scope[:scope])
      |> assign(:current_nav, assigns.current_scope && assigns.current_scope[:current_nav])

    ~H"""
    <%= if @scope != :public do %>
      <header class="sticky top-0 z-40 shrink-0 px-4 sm:px-6 lg:px-8 xl:px-12 2xl:px-16 border-b border-base-300 bg-base-100/95 backdrop-blur supports-backdrop-filter:bg-base-100/80">
        <div class="flex items-center justify-between h-16">
          <div class="flex items-center gap-3">
            <a href="/" class="flex items-center gap-2">
              <img src={~p"/images/logo.svg"} width="32" height="32" />
              <span class="text-base font-semibold tracking-tight text-base-content">
                Dobby Admin
              </span>
            </a>
            <span class="text-xs uppercase tracking-[0.3em] text-base-content/60">
              Control Center
            </span>
          </div>
          <div class="flex items-center gap-4">
            <div class="flex items-center gap-3">
              <div class="text-xs text-base-content/60 uppercase tracking-[0.3em]">Theme</div>
              <.theme_toggle />
            </div>
            <.link
              href={~p"/admin/session"}
              method="delete"
              data-confirm="Log out from the admin?"
              class="inline-flex items-center gap-2 rounded-full border border-base-300 bg-base-100/60 px-4 py-2 text-sm font-semibold text-base-content/80 hover:bg-base-200/70 hover:text-base-content transition-colors duration-200"
            >
              <span>Log Out</span>
            </.link>
          </div>
        </div>
      </header>
    <% end %>

    <main class={[
      @scope == :public && "py-0 min-h-screen",
      @scope != :public &&
        "flex h-full min-h-screen flex-col bg-base-100 text-base-content transition-colors duration-300"
    ]}>
      <div :if={@scope == :public} class="w-full">
        {render_slot(@inner_block)}
      </div>

      <div
        :if={@scope != :public}
        class="flex flex-1 overflow-hidden bg-gradient-to-b from-base-100 via-base-100 to-base-200"
      >
        <aside class="hidden lg:flex w-72 flex-shrink-0 border-r border-base-300 bg-base-100/90 p-6 backdrop-blur overflow-y-auto">
          <div class="flex flex-col gap-6 w-full">
            <nav class="space-y-2">
              <ul class="flex flex-col gap-2">
                <li :for={item <- all_nav_items()}>
                  <.nav_link item={item} current_nav={@current_nav} />
                </li>
              </ul>
            </nav>
          </div>
        </aside>
        <div class="flex-1 overflow-y-auto p-6 lg:p-10 bg-base-200/60 dark:bg-base-200/40">
          {render_slot(@inner_block)}
        </div>
      </div>
    </main>

    <.flash_group flash={@flash} />
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
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
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
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
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
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

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

  attr :item, :map, required: true
  attr :current_nav, :atom, default: nil

  defp nav_link(assigns) do
    active? = assigns.item[:key] && assigns.item[:key] == assigns.current_nav

    assigns =
      assign(assigns, :active?, active? == true)

    ~H"""
    <%= if @item.href do %>
      <.link
        navigate={@item.href}
        class={[
          "group relative flex items-center gap-3 rounded-xl px-4 py-3 transition-all duration-200 border-l-4",
          @active? && "bg-primary/10 border-primary shadow-sm",
          not @active? && "border-transparent hover:bg-base-200/80 hover:shadow-sm"
        ]}
      >
        <!-- 左侧激活指示条 -->
        <div :if={@active?} class="absolute left-0 top-0 bottom-0 w-1 bg-primary rounded-r-full">
        </div>

        <div class="flex items-center gap-3 flex-1 min-w-0">
          <.icon
            name={@item.icon}
            class={
              if @active?,
                do: "h-5 w-5 flex-shrink-0 transition-colors text-primary",
                else:
                  "h-5 w-5 flex-shrink-0 transition-colors text-base-content/50 group-hover:text-base-content"
            }
          />
          <div class="flex-1 min-w-0">
            <p class={[
              "text-sm font-semibold truncate text-base-content",
              not @active? && "text-base-content/80"
            ]}>
              {@item.label}
              <span
                :if={@item[:badge]}
                class={[
                  "ml-2 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide",
                  @active? && "bg-primary/20 text-primary",
                  not @active? && "bg-base-200 text-base-content/70"
                ]}
              >
                {@item.badge}
              </span>
            </p>
            <p class={[
              "text-xs truncate mt-0.5 text-base-content/70",
              @active? && "text-primary"
            ]}>
              {@item.caption}
            </p>
          </div>
        </div>
        <.icon
          name="hero-chevron-right"
          class={
            if @active?,
              do:
                "h-4 w-4 flex-shrink-0 transition-transform group-hover:translate-x-0.5 text-primary",
              else:
                "h-4 w-4 flex-shrink-0 transition-transform group-hover:translate-x-0.5 text-base-content/40"
          }
        />
      </.link>
    <% else %>
      <div class="flex items-center gap-3 rounded-xl px-4 py-3 border border-dashed border-base-300 bg-base-200/60 text-base-content/50 cursor-not-allowed">
        <.icon name={@item.icon} class="h-5 w-5 text-base-content/30" />
        <div class="flex-1 min-w-0">
          <p class="text-sm font-semibold text-base-content/60">{@item.label}</p>
          <p class="text-xs text-base-content/50 mt-0.5">敬請期待</p>
        </div>
        <span class="text-[10px] uppercase tracking-[0.3em] text-base-content/30">Soon</span>
      </div>
    <% end %>
    """
  end

  defp all_nav_items do
    nav_sections()
    |> Enum.flat_map(& &1.items)
  end

  defp nav_sections do
    [
      %{
        title: "作業中心",
        items: [
          %{
            label: "Dashboard",
            caption: "KPI 與控制塔",
            href: ~p"/admin",
            icon: "hero-chart-bar-square",
            key: :dashboard
          },
          %{
            label: "Campaigns",
            caption: "活動 / 刮卡設定",
            href: ~p"/admin/campaigns",
            icon: "hero-ticket",
            key: :campaigns
          }
        ]
      },
      %{
        title: "獎品 / 券碼",
        items: [
          %{
            label: "Prize Library",
            caption: "跨活動獎品集中管理",
            href: ~p"/admin/prize-library",
            icon: "hero-gift",
            key: :prize_library
          }
        ]
      },
      %{
        title: "通知 / 報表",
        items: [
          %{
            label: "Email Templates",
            caption: "維護全局郵件模板",
            href: ~p"/admin/email-templates",
            icon: "hero-envelope",
            key: :email_templates
          },
          %{
            label: "Email Logs",
            caption: "查看所有郵件發送歷史",
            href: ~p"/admin/email-logs",
            icon: "hero-envelope-open",
            key: :email_logs
          }
        ]
      }
    ]
  end
end
