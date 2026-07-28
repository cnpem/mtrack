defmodule MouseTrackerWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MouseTrackerWeb, :html

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
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://phoenix.hexdocs.pm/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Auth screens shell (login/register/confirmation): centered card on the same
  light Locomo palette as `locomo/1` (no sidebar, since the user isn't signed
  in yet at this point).

  ## Examples

      <Layouts.auth flash={@flash} current_scope={@current_scope}>
        <h1>Content</h1>
      </Layouts.auth>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <div class="font-ui flex min-h-screen flex-col items-center justify-center bg-[#f3f4f6] px-4 py-12 text-[#0f1729]">
      <.link navigate={~p"/"} class="mb-8 flex items-center gap-2.5">
        <div class="flex size-9 items-center justify-center rounded-[9px] bg-[#CC5500] text-white">
          <.icon name="hero-viewfinder-circle" class="size-5" />
        </div>
        <div class="text-left leading-tight">
          <div class="text-[15px] font-semibold text-[#0f1729]">Locomo</div>
          <div class="font-data text-[10.5px] text-[#8a93a3]">locomotion tracking</div>
        </div>
      </.link>

      <main class="w-full max-w-sm rounded-2xl border border-[#e7e9ee] bg-white p-7 shadow-sm">
        {render_slot(@inner_block)}
      </main>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  The Locomo application shell: fixed dark sidebar (248px) + sticky topbar,
  built in pure Tailwind per the design handoff (see CLAUDE.md Sprint 3).

  Used by the domain LiveViews (experiments, processing, results). The auth
  screens keep using `app/1`. Pass `active` to highlight the current nav item
  and `breadcrumb`/`title` for the topbar.

  ## Examples

      <Layouts.locomo flash={@flash} current_scope={@current_scope} active={:experiments}>
        <h1>Content</h1>
      </Layouts.locomo>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :active, :atom,
    default: :experiments,
    doc: "which sidebar nav item is active (:experiments | :datasets | :analyses | :settings)"

  attr :breadcrumb, :string, default: nil, doc: "section label shown at the left of the topbar"

  attr :page_title, :string,
    default: nil,
    doc: "current item shown at the right of the breadcrumb"

  slot :inner_block, required: true

  def locomo(assigns) do
    ~H"""
    <div class="font-ui min-h-screen bg-[#f3f4f6] text-[#0f1729]">
      <aside class="fixed inset-y-0 left-0 z-20 flex w-[248px] flex-col bg-[#1a212e] text-[#cbd2dc]">
        <div class="flex items-center gap-2.5 px-5 py-4">
          <div class="flex size-8 items-center justify-center rounded-[9px] bg-[#CC5500] text-white">
            <.icon name="hero-viewfinder-circle" class="size-5" />
          </div>
          <div class="leading-tight">
            <div class="text-[13.5px] font-semibold text-white">Locomo</div>
            <div class="font-data text-[10.5px] text-[#7e8794]">locomotion tracking</div>
          </div>
        </div>

        <nav class="mt-2 flex flex-1 flex-col gap-1 px-3">
          <.sidebar_link
            navigate={~p"/experiments"}
            icon="hero-rectangle-stack"
            label="Experiments"
            active={@active == :experiments}
          />
          <.sidebar_link
            navigate={~p"/datasets"}
            icon="hero-circle-stack"
            label="Datasets"
            active={@active == :datasets}
          />
          <.sidebar_link
            navigate={~p"/analyses"}
            icon="hero-chart-bar"
            label="Analyses"
            active={@active == :analyses}
          />
          <.sidebar_link
            navigate={~p"/pipeline-settings"}
            icon="hero-cog-6-tooth"
            label="Pipeline settings"
            active={@active == :settings}
          />
        </nav>

        <div class="border-t border-[#2b3444] p-3">
          <div class="flex items-center gap-2.5 rounded-[9px] px-2 py-1.5">
            <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-[#2b3444] text-[11px] font-semibold text-[#cbd2dc]">
              {user_initials(@current_scope)}
            </div>
            <div class="min-w-0 flex-1 leading-tight">
              <div class="truncate font-data text-[11.5px] text-[#cbd2dc]">
                {user_email(@current_scope)}
              </div>
              <.link
                href={~p"/users/log-out"}
                method="delete"
                class="text-[10.5px] text-[#7e8794] hover:text-[#cbd2dc]"
              >
                Sign out
              </.link>
            </div>
          </div>
        </div>
      </aside>

      <div class="pl-[248px]">
        <header class="sticky top-0 z-10 flex h-[58px] items-center gap-3 border-b border-[#e7e9ee] bg-[#f3f4f6]/[.82] px-6 backdrop-blur">
          <div class="flex items-center gap-1.5 text-[13px]">
            <span :if={@breadcrumb} class="text-[#8a93a3]">{@breadcrumb}</span>
            <.icon :if={@breadcrumb} name="hero-chevron-right-micro" class="size-3.5 text-[#b0b7c1]" />
            <span class="font-medium text-[#344054]">{assigns[:page_title] || "Experiments"}</span>
          </div>
        </header>

        <main class="px-6 py-7">
          {render_slot(@inner_block)}
        </main>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp sidebar_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[
        "flex items-center gap-3 rounded-[9px] px-3 py-2 text-[13px] font-medium transition-colors",
        @active && "bg-[#CC5500] text-white",
        !@active && "text-[#cbd2dc] hover:bg-[#0f1729] hover:text-white"
      ]}
    >
      <.icon name={@icon} class="size-[18px]" />
      {@label}
    </.link>
    """
  end

  defp user_email(%{user: %{email: email}}), do: email
  defp user_email(_), do: ""

  defp user_initials(%{user: %{email: email}}) when is_binary(email) do
    email |> String.first() |> String.upcase()
  end

  defp user_initials(_), do: "?"

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
