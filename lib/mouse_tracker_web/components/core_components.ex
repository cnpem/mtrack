defmodule MouseTrackerWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework.
  Here are useful references:

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: MouseTrackerWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed top-4 right-4 z-50 flex flex-col items-end gap-2"
      {@rest}
    >
      <div class={[
        "flex w-80 sm:w-96 max-w-80 sm:max-w-96 items-start gap-3 rounded-[10px] border p-3.5 text-sm text-wrap shadow-md",
        @kind == :info && "border-[#bfdbfe] bg-[#eff6ff] text-[#1e3a8a]",
        @kind == :error && "border-red-200 bg-red-50 text-red-800"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" =>
        "inline-flex items-center justify-center gap-1.5 rounded-[8px] bg-[#CC5500] px-4 py-2 text-[13px] font-semibold text-white hover:bg-[#b34a00] disabled:cursor-not-allowed disabled:opacity-50",
      nil =>
        "inline-flex items-center justify-center gap-1.5 rounded-[8px] border border-[#f0d3b8] bg-[#fbeee4] px-4 py-2 text-[13px] font-semibold text-[#b34a00] hover:bg-[#f6e2cf] disabled:cursor-not-allowed disabled:opacity-50"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        Map.fetch!(variants, assigns[:variant])
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-2">
      <label for={@id} class="flex items-center gap-2 text-sm text-[#344054]">
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class={
            @class ||
              "size-4 rounded border-[#d0d5dd] accent-[#CC5500] focus:ring-2 focus:ring-[#CC5500]/30 focus:outline-none"
          }
          {@rest}
        />{@label}
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-[#344054]">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-2.5 text-[14px] text-[#0f1729] focus:border-[#CC5500] focus:outline-none disabled:cursor-not-allowed disabled:opacity-60",
            @errors != [] && (@error_class || "border-red-400 focus:border-red-500")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-[#344054]">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-2.5 text-[14px] text-[#0f1729] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none disabled:cursor-not-allowed disabled:opacity-60",
            @errors != [] && (@error_class || "border-red-400 focus:border-red-500")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="mb-2">
      <label for={@id}>
        <span :if={@label} class="mb-1 block text-sm font-medium text-[#344054]">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class ||
              "w-full rounded-[8px] border border-[#e7e9ee] bg-white px-3 py-2.5 text-[14px] text-[#0f1729] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none disabled:cursor-not-allowed disabled:opacity-60",
            @errors != [] && (@error_class || "border-red-400 focus:border-red-500")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-red-600">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-[#8a93a3]">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="w-full text-left text-sm">
      <thead class="border-b border-[#e7e9ee] text-[11px] font-semibold uppercase tracking-wide text-[#8a93a3]">
        <tr>
          <th :for={col <- @col} class="px-3 py-2">{col[:label]}</th>
          <th :if={@action != []} class="px-3 py-2">
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class="border-b border-[#e7e9ee] odd:bg-white even:bg-[#fafbfc] hover:bg-[#f7f8fa]"
        >
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={["px-3 py-2.5", @row_click && "hover:cursor-pointer"]}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 px-3 py-2.5 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="divide-y divide-[#e7e9ee]">
      <li :for={item <- @item} class="flex items-center gap-4 py-3">
        <div class="min-w-0 flex-1">
          <div class="text-sm font-semibold text-[#0f1729]">{item.title}</div>
          <div class="text-sm text-[#344054]">{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Dashed empty-state box used by list-like screens (no results after a
  search/filter, or nothing to show yet). Pass `title`/`subtitle`, an
  optional `icon` (rendered inside a circle above the title), and any CTA
  markup as the default slot.

  ## Examples

      <.empty_state icon="hero-beaker" title="No experiments yet" subtitle="..." />

      <.empty_state :if={@videos == []} class="mt-6" title="No videos yet">
        <.link navigate={~p"/experiments/new"}>Upload a video</.link>
      </.empty_state>
  """
  attr :icon, :string, default: nil
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class={[
      "flex flex-col items-center rounded-[13px] border border-dashed border-[#d4d8df] bg-white px-6 py-16 text-center",
      @class
    ]}>
      <div
        :if={@icon}
        class="flex size-12 items-center justify-center rounded-full bg-[#f2f4f7] text-[#98a2b3]"
      >
        <.icon name={@icon} class="size-6" />
      </div>
      <h2 class={["text-[15px] font-bold text-[#0f1729]", @icon && "mt-4"]}>{@title}</h2>
      <p :if={@subtitle} class="mt-1 max-w-sm text-[13px] text-[#667085]">{@subtitle}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Search box (`phx-change="search"`, submitting a `query` param) used by list
  screens (Experiments, Datasets, Pipeline Settings).
  """
  attr :id, :string, default: nil
  attr :query, :string, required: true
  attr :placeholder, :string, default: "Search"
  attr :class, :any, default: "relative w-full max-w-[320px]"

  def search_input(assigns) do
    ~H"""
    <form id={@id} phx-change="search" class={@class}>
      <.icon
        name="hero-magnifying-glass-micro"
        class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[#98a2b3]"
      />
      <input
        type="text"
        name="query"
        value={@query}
        phx-debounce="200"
        placeholder={@placeholder}
        autocomplete="off"
        class="w-full rounded-[8px] border border-[#e7e9ee] bg-white py-2 pl-9 pr-3 text-[13px] text-[#0f1729] placeholder:text-[#98a2b3] focus:border-[#CC5500] focus:outline-none"
      />
    </form>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(MouseTrackerWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(MouseTrackerWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
