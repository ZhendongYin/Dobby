defmodule DobbyWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: DobbyWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
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
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
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
  Renders a button with navigation support using pure Tailwind CSS.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled phx-click phx-submit)

  attr :class, :string, default: ""
  attr :variant, :string, values: ~w(primary), default: "primary"
  attr :size, :string, values: ~w(sm md lg), default: "md"
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    base_classes =
      "inline-flex items-center justify-center gap-2 rounded-xl font-semibold shadow-md transition-all disabled:opacity-50 disabled:cursor-not-allowed active:scale-95"

    variant_classes = %{
      "primary" => "bg-indigo-600 text-white hover:bg-indigo-700"
    }

    size_classes = %{
      "sm" => "px-4 py-2 text-sm",
      "md" => "px-5 py-2.5 text-sm",
      "lg" => "px-6 py-3 text-base"
    }

    variant_class = Map.fetch!(variant_classes, assigns[:variant])
    size_class = Map.fetch!(size_classes, assigns[:size])

    assigns =
      assign_new(assigns, :class, fn ->
        [base_classes, variant_class, size_class, assigns[:class]]
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
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

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

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
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
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
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
    assigns =
      assigns
      |> assign(:has_errors, assigns[:errors] != [] && assigns[:errors] != nil)
      |> assign(:has_value, !is_nil(assigns[:value]) && assigns[:value] != "")

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">
          {@label}
          <span :if={@rest[:required]} class="text-red-500 ml-1">*</span>
        </span>
        <div class="relative">
          <input
            type={@type}
            name={@name}
            id={@id}
            value={Phoenix.HTML.Form.normalize_value(@type, @value)}
            class={[
              @class || "w-full input",
              @has_errors &&
                (@error_class || "input-error border-red-300 focus:border-red-500 focus:ring-red-500"),
              !@has_errors && @has_value &&
                "border-green-300 focus:border-green-500 focus:ring-green-500"
            ]}
            phx-debounce={@rest[:phx_debounce] || "300"}
            {@rest}
          />
          <span
            :if={!@has_errors && @has_value}
            class="absolute right-3 top-1/2 -translate-y-1/2"
            title="驗證通過"
          >
            <.icon name="hero-check-circle" class="h-5 w-5 text-green-500" />
          </span>
        </div>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
      <p :if={!@has_errors && @rest[:help_text]} class="mt-1 text-xs text-gray-500">
        {@rest[:help_text]}
      </p>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a loading spinner.

  ## Examples

      <.spinner />
      <.spinner size="lg" />
      <.spinner class="text-indigo-600" />
  """
  attr :size, :string, default: "md", values: ~w(xs sm md lg xl)
  attr :class, :string, default: ""
  attr :text, :string, default: nil, doc: "optional text to display below spinner"

  def spinner(assigns) do
    size_classes = %{
      "xs" => "h-3 w-3",
      "sm" => "h-4 w-4",
      "md" => "h-6 w-6",
      "lg" => "h-8 w-8",
      "xl" => "h-12 w-12"
    }

    size_class = Map.fetch!(size_classes, assigns[:size] || "md")

    assigns = assign(assigns, :size_class, size_class)

    ~H"""
    <div class="flex flex-col items-center justify-center gap-2">
      <div class={[
        "loading loading-spinner",
        @size_class,
        @class
      ]}>
      </div>
      <p :if={@text} class="text-sm text-gray-500">{@text}</p>
    </div>
    """
  end

  @doc """
  Renders a loading overlay that covers the entire container.

  ## Examples

      <.loading_overlay :if={@loading} />
  """
  attr :show, :boolean, default: true
  attr :text, :string, default: "載入中...", doc: "loading text to display"

  def loading_overlay(assigns) do
    ~H"""
    <div
      :if={@show}
      class="absolute inset-0 z-50 flex items-center justify-center bg-white/80 backdrop-blur-sm"
      role="status"
      aria-label="Loading"
    >
      <div class="flex flex-col items-center gap-3">
        <.spinner size="lg" class="text-indigo-600" />
        <p class="text-sm font-medium text-gray-700">{@text}</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a friendly error message with icon and helpful text.

  ## Examples

      <.error_message message="Something went wrong" />
      <.error_message title="Error" message="Failed to save" />
  """
  attr :title, :string, default: nil
  attr :message, :string, required: true
  attr :class, :string, default: ""

  def error_message(assigns) do
    ~H"""
    <div class={["rounded-lg bg-red-50 border border-red-200 p-4", @class]}>
      <div class="flex items-start gap-3">
        <.icon name="hero-exclamation-circle" class="h-5 w-5 text-red-600 flex-shrink-0 mt-0.5" />
        <div class="flex-1">
          <h3 :if={@title} class="text-sm font-semibold text-red-900 mb-1">
            {@title}
          </h3>
          <p class="text-sm text-red-800">{@message}</p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a success message with icon.

  ## Examples

      <.success_message message="Saved successfully" />
  """
  attr :message, :string, required: true
  attr :class, :string, default: ""

  def success_message(assigns) do
    ~H"""
    <div class={["rounded-lg bg-green-50 border border-green-200 p-4", @class]}>
      <div class="flex items-center gap-3">
        <.icon name="hero-check-circle" class="h-5 w-5 text-green-600 flex-shrink-0" />
        <p class="text-sm font-medium text-green-800">{@message}</p>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with loading state support.

  Automatically shows loading spinner when phx-click-loading or phx-submit-loading is active.

  ## Examples

      <.button_with_loading phx-click="save">Save</.button_with_loading>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :string, default: ""
  attr :variant, :string, values: ~w(primary secondary danger), default: "primary"
  slot :inner_block, required: true

  def button_with_loading(assigns) do
    variant_classes = %{
      "primary" => "bg-indigo-600 text-white hover:bg-indigo-700",
      "secondary" => "border border-slate-200 bg-white text-slate-700 hover:bg-slate-50",
      "danger" => "bg-red-600 text-white hover:bg-red-700"
    }

    base_classes =
      "inline-flex items-center justify-center gap-2 rounded-xl font-semibold shadow-md transition-all disabled:opacity-50 disabled:cursor-not-allowed active:scale-95 px-5 py-2.5 text-sm"

    variant_class = Map.fetch!(variant_classes, assigns[:variant] || "primary")

    assigns =
      assigns
      |> assign(:base_classes, base_classes)
      |> assign(:variant_class, variant_class)

    ~H"""
    <button
      class={[
        @base_classes,
        @variant_class,
        @class
      ]}
      {@rest}
    >
      <span class="phx-click-loading:hidden phx-submit-loading:hidden">
        {render_slot(@inner_block)}
      </span>
      <span class="hidden phx-click-loading:inline phx-submit-loading:inline flex items-center gap-2">
        <.spinner size="sm" class="text-current" />
        <span>處理中...</span>
      </span>
    </button>
    """
  end

  @doc """
  Renders a skeleton loading placeholder.

  ## Examples

      <.skeleton_loader />
      <.skeleton_loader lines={3} />
      <.skeleton_loader variant="card" />
  """
  attr :lines, :integer, default: 1
  attr :variant, :string, values: ~w(text card table), default: "text"
  attr :class, :string, default: ""

  def skeleton_loader(assigns) do
    ~H"""
    <div class={["skeleton rounded", @class]}>
      <%= case @variant do %>
        <% "text" -> %>
          <div :for={_i <- 1..@lines} class="h-4 bg-gray-200 rounded mb-2"></div>
          <div :if={@lines > 1} class="h-4 bg-gray-200 rounded w-3/4"></div>
        <% "card" -> %>
          <div class="space-y-4">
            <div class="h-48 bg-gray-200 rounded-lg"></div>
            <div class="space-y-2">
              <div class="h-4 bg-gray-200 rounded w-3/4"></div>
              <div class="h-4 bg-gray-200 rounded w-1/2"></div>
            </div>
          </div>
        <% "table" -> %>
          <div class="space-y-3">
            <div :for={_i <- 1..@lines} class="flex gap-4">
              <div class="h-4 bg-gray-200 rounded flex-1"></div>
              <div class="h-4 bg-gray-200 rounded w-24"></div>
              <div class="h-4 bg-gray-200 rounded w-32"></div>
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a responsive container with smooth animations.

  ## Examples

      <.animated_container>
        Content here
      </.animated_container>
  """
  attr :animation, :string,
    default: "fade-in",
    values: ~w(fade-in slide-in-right slide-in-left scale-in)

  attr :class, :string, default: ""

  slot :inner_block, required: true

  def animated_container(assigns) do
    animation_class = "animate-#{assigns[:animation]}"
    assigns = assign(assigns, :animation_class, animation_class)

    ~H"""
    <div class={[@animation_class, @class]}>
      {render_slot(@inner_block)}
    </div>
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
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a unified card component using pure Tailwind CSS.

  ## Examples

      <.card>
        内容
      </.card>

      <.card variant="elevated">
        带阴影的卡片
      </.card>
  """
  attr :variant, :string, values: ~w(default elevated), default: "default"
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def card(assigns) do
    base_classes =
      "rounded-2xl border border-base-300 bg-base-100/95 text-base-content shadow-sm p-6 transition-colors duration-300 backdrop-blur supports-[backdrop-filter]:bg-base-100/80"

    variant_classes = %{
      "default" => "",
      "elevated" => "shadow-xl shadow-primary/20"
    }

    variant_class = Map.fetch!(variant_classes, assigns[:variant])

    assigns =
      assigns
      |> assign(:base_classes, base_classes)
      |> assign(:variant_class, variant_class)

    ~H"""
    <div class={[@base_classes, @variant_class, @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a primary button using pure Tailwind CSS.

  ## Examples

      <.primary_button phx-click="save">保存</.primary_button>
      <.primary_button navigate={~p"/admin"}>返回</.primary_button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled phx-click phx-submit)

  attr :class, :string, default: ""
  attr :size, :string, values: ~w(sm md lg), default: "md"
  slot :inner_block, required: true

  def primary_button(assigns) do
    base_classes =
      "inline-flex items-center justify-center gap-2 rounded-xl bg-indigo-600 text-white font-semibold shadow-md hover:bg-indigo-700 active:scale-95 transition-all disabled:opacity-50 disabled:cursor-not-allowed"

    size_classes = %{
      "sm" => "px-4 py-2 text-sm",
      "md" => "px-5 py-2.5 text-sm",
      "lg" => "px-6 py-3 text-base"
    }

    assigns =
      assigns
      |> assign(:base_classes, base_classes)
      |> assign(:size_class, Map.fetch!(size_classes, assigns[:size]))

    if assigns.rest[:href] || assigns.rest[:navigate] || assigns.rest[:patch] do
      ~H"""
      <.link class={[@base_classes, @size_class, @class]} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={[@base_classes, @size_class, @class]} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a secondary button using pure Tailwind CSS.

  ## Examples

      <.secondary_button phx-click="cancel">取消</.secondary_button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled phx-click phx-submit)

  attr :class, :string, default: ""
  attr :size, :string, values: ~w(sm md lg), default: "md"
  slot :inner_block, required: true

  def secondary_button(assigns) do
    base_classes =
      "inline-flex items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white text-slate-700 font-semibold hover:bg-slate-50 active:scale-95 transition-all disabled:opacity-50 disabled:cursor-not-allowed"

    size_classes = %{
      "sm" => "px-4 py-2 text-sm",
      "md" => "px-5 py-2.5 text-sm",
      "lg" => "px-6 py-3 text-base"
    }

    assigns =
      assigns
      |> assign(:base_classes, base_classes)
      |> assign(:size_class, Map.fetch!(size_classes, assigns[:size]))

    if assigns.rest[:href] || assigns.rest[:navigate] || assigns.rest[:patch] do
      ~H"""
      <.link class={[@base_classes, @size_class, @class]} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={[@base_classes, @size_class, @class]} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a unified page container using pure Tailwind CSS.

  ## Examples

      <.page_container>
        <h1>页面标题</h1>
      </.page_container>
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def page_container(assigns) do
    ~H"""
    <div class={["px-4 sm:px-6 lg:px-8 xl:px-12 2xl:px-16 max-w-[95%] mx-auto space-y-8", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a unified page header using pure Tailwind CSS.

  ## Examples

      <.page_header title="Campaigns" subtitle="管理所有活動" />
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :class, :string, default: ""

  def page_header(assigns) do
    ~H"""
    <div class={["mb-8", @class]}>
      <h1 class="text-3xl font-semibold text-base-content">{@title}</h1>
      <p :if={@subtitle} class="mt-2 text-sm text-base-content/70">{@subtitle}</p>
    </div>
    """
  end

  @doc """
  Provides a consistent layout shell for admin create/edit pages.
  """
  attr :back_href, :string, required: true
  attr :back_label, :string, default: "返回列表"
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :eyebrow, :string, default: nil
  attr :id, :string, default: nil
  slot :actions
  slot :form, required: true
  slot :sidebar

  def admin_form_shell(assigns) do
    ~H"""
    <section id={@id} class="space-y-6">
      <.link
        navigate={@back_href}
        class="inline-flex items-center gap-2 text-sm text-base-content/60 hover:text-base-content transition-colors"
      >
        <.icon name="hero-arrow-left" class="w-4 h-4" /> {@back_label}
      </.link>

      <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div class="space-y-2">
          <p :if={@eyebrow} class="text-xs uppercase tracking-[0.3em] text-base-content/50">
            {@eyebrow}
          </p>
          <h1 class="text-3xl font-semibold text-base-content">{@title}</h1>
          <p :if={@subtitle} class="text-sm text-base-content/70 max-w-2xl">
            {@subtitle}
          </p>
        </div>

        <div :if={@actions != []} class="flex flex-col gap-2 sm:flex-row sm:items-center">
          {render_slot(@actions)}
        </div>
      </div>

      <div class={[
        @sidebar == [] && "max-w-4xl",
        @sidebar != [] && "grid gap-6 lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]"
      ]}>
        <div class="rounded-3xl border border-base-300 bg-base-100/95 p-6 shadow-sm space-y-6">
          {render_slot(@form)}
        </div>

        <div
          :if={@sidebar != []}
          class="rounded-3xl border border-base-300 bg-base-100/80 p-6 shadow-sm space-y-6"
        >
          {render_slot(@sidebar)}
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders a unified search input component using pure Tailwind CSS.

  ## Examples

      <.search_input
        name="search"
        value={@search}
        placeholder="搜尋..."
        phx-change="search"
      />

      <.search_input
        name="filter[search]"
        value={@filter.search}
        placeholder="搜尋..."
        in_form={true}
      />
  """
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: "搜尋..."
  attr :phx_change, :string, default: "search"
  attr :phx_debounce, :string, default: "300"
  attr :in_form, :boolean, default: false, doc: "如果为 true，只渲染 input，不包含 form 标签"
  attr :class, :string, default: ""
  attr :rest, :global

  def search_input(assigns) do
    assigns = assign(assigns, :rest_attrs, assigns.rest || %{})

    if assigns.in_form do
      ~H"""
      <.search_input_inner
        name={@name}
        value={@value}
        placeholder={@placeholder}
        phx_debounce={@phx_debounce}
        class={@class}
        rest_attrs={@rest_attrs}
      />
      """
    else
      ~H"""
      <form phx-change={@phx_change} phx-debounce={@phx_debounce}>
        <.search_input_inner
          name={@name}
          value={@value}
          placeholder={@placeholder}
          phx_debounce={@phx_debounce}
          class={@class}
          rest_attrs={@rest_attrs}
        />
      </form>
      """
    end
  end

  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: "搜尋..."
  attr :phx_debounce, :string, default: "300"
  attr :class, :string, default: ""
  attr :rest_attrs, :map, default: %{}

  defp search_input_inner(assigns) do
    assigns = assign(assigns, :container_classes, ["relative", assigns.class])

    ~H"""
    <div class={@container_classes}>
      <.icon
        name="hero-magnifying-glass"
        class="absolute left-3 top-3.5 h-5 w-5 text-base-content/40"
      />
      <input
        type="text"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        phx-debounce={@phx_debounce}
        class="w-full rounded-xl border border-base-300 bg-base-100/90 py-3 pl-10 pr-4 text-sm text-base-content placeholder:text-base-content/40 shadow-sm focus:border-primary focus:ring-primary"
        {@rest_attrs}
      />
    </div>
    """
  end

  @doc """
  Renders a select dropdown component.

  ## Examples

      <.select
        name="status"
        value={@status}
        options={[{"all", "全部"}, {"active", "啟用"}, {"disabled", "停用"}]}
        phx-change="filter"
      />

      <.select
        name="campaign_id"
        value={@campaign_id}
        options={@campaigns}
        option_key={:id}
        option_label={:name}
        placeholder="選擇活動"
      />
  """
  attr :name, :string, required: true
  attr :value, :string, default: ""

  attr :options, :list,
    required: true,
    doc: "List of {value, label} tuples or list of maps/structs"

  attr :option_key, :atom,
    default: nil,
    doc: "If options are maps/structs, the key to use for value"

  attr :option_label, :atom,
    default: nil,
    doc: "If options are maps/structs, the key to use for label"

  attr :placeholder, :string, default: nil
  attr :phx_change, :string, default: nil
  attr :class, :string, default: ""
  attr :id, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :rest, :global

  def select(assigns) do
    options_html =
      build_options(assigns.options, assigns.option_key, assigns.option_label, assigns.value)

    id = assigns.id || "select-#{assigns.name}"

    # Get phx_change from assigns - try multiple ways to ensure we get it
    # Phoenix may put it in different places depending on how it's passed
    phx_change =
      assigns[:phx_change] ||
        assigns.phx_change ||
        Map.get(assigns.rest || %{}, :phx_change) ||
        Map.get(assigns.rest || %{}, :"phx-change") ||
        Map.get(assigns.rest || %{}, "phx-change")

    # Remove phx-change from rest if it exists there
    rest = Map.drop(assigns.rest || %{}, [:phx_change, :"phx-change", "phx-change"])

    form_id = "form-#{id}"

    assigns =
      assigns
      |> assign(:options_html, options_html)
      |> assign(:id, id)
      |> assign(:form_id, form_id)
      |> assign(:phx_change, phx_change)
      |> assign(:rest, rest)

    # If phx-change is provided, wrap in a form
    if phx_change do
      ~H"""
      <form id={@form_id} phx-change={@phx_change}>
        <select
          id={@id}
          name={@name}
          value={@value}
          class={[
            "w-full rounded-xl border border-base-300 bg-base-100/90 px-3 py-3 text-sm text-base-content placeholder:text-base-content/40 shadow-sm focus:border-primary focus:ring-primary",
            @class
          ]}
          disabled={@disabled}
          {@rest}
        >
          <option :if={@placeholder} value="">{@placeholder}</option>
          {Phoenix.HTML.raw(@options_html)}
        </select>
      </form>
      """
    else
      ~H"""
      <select
        id={@id}
        name={@name}
        value={@value}
        class={[
          "w-full rounded-xl border border-base-300 bg-base-100/90 px-3 py-3 text-sm text-base-content placeholder:text-base-content/40 shadow-sm focus:border-primary focus:ring-primary",
          @class
        ]}
        disabled={@disabled}
        {@rest}
      >
        <option :if={@placeholder} value="">{@placeholder}</option>
        {Phoenix.HTML.raw(@options_html)}
      </select>
      """
    end
  end

  defp build_options(options, nil, nil, selected_value) when is_list(options) do
    options
    |> Enum.map(fn
      {value, label} ->
        selected = if to_string(value) == to_string(selected_value), do: " selected", else: ""

        ~s(<option value="#{escape_html(to_string(value))}"#{selected}>#{escape_html(to_string(label))}</option>)

      value when is_binary(value) ->
        selected = if to_string(value) == to_string(selected_value), do: " selected", else: ""
        ~s(<option value="#{escape_html(value)}"#{selected}>#{escape_html(value)}</option>)
    end)
    |> Enum.join("\n")
  end

  defp build_options(options, key, label, selected_value)
       when is_list(options) and not is_nil(key) and not is_nil(label) do
    options
    |> Enum.map(fn option ->
      option_value = Map.get(option, key) || Map.get(option, Atom.to_string(key))
      option_label = Map.get(option, label) || Map.get(option, Atom.to_string(label))

      selected =
        if to_string(option_value) == to_string(selected_value), do: " selected", else: ""

      ~s(<option value="#{escape_html(to_string(option_value))}"#{selected}>#{escape_html(to_string(option_label))}</option>)
    end)
    |> Enum.join("\n")
  end

  defp escape_html(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  @doc """
  Renders a unified badge component using pure Tailwind CSS.

  ## Examples

      <.badge>New</.badge>
      <.badge variant="success">Active</.badge>
  """
  attr :variant, :string, values: ~w(default success warning error info), default: "default"
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def badge(assigns) do
    variant_classes = %{
      "default" => "bg-slate-100 text-slate-700",
      "success" => "bg-emerald-50 text-emerald-700",
      "warning" => "bg-amber-50 text-amber-700",
      "error" => "bg-red-50 text-red-700",
      "info" => "bg-indigo-50 text-indigo-700"
    }

    base_classes = "inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold"

    assigns =
      assigns
      |> assign(:base_classes, base_classes)
      |> assign(:variant_class, Map.fetch!(variant_classes, assigns[:variant]))

    ~H"""
    <span class={[@base_classes, @variant_class, @class]}>
      {render_slot(@inner_block)}
    </span>
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
    <table class="min-w-full divide-y divide-base-300 bg-base-100 text-base-content text-sm rounded-2xl overflow-hidden">
      <thead class="bg-base-200/80 text-xs font-semibold uppercase tracking-[0.2em] text-base-content/70">
        <tr>
          <th :for={col <- @col} class="px-4 py-3 text-left">{col[:label]}</th>
          <th :if={@action != []} class="px-4 py-3 text-right">
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody
        id={@id}
        phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
        class="divide-y divide-base-200 bg-base-100"
      >
        <tr
          :for={row <- @rows}
          id={@row_id && @row_id.(row)}
          class="hover:bg-base-200/50 transition-colors"
        >
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={["px-4 py-4", @row_click && "hover:cursor-pointer"]}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold px-4 py-4">
            <div class="flex gap-4 justify-end">
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
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
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
  attr :class, :string, default: "size-4"

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
      Gettext.dngettext(DobbyWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(DobbyWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders a sortable table header.

  ## Examples

      <.sortable_header
        field="name"
        current_sort={@sort_by}
        current_order={@sort_order}
        label="名稱"
        phx_click="sort"
      />
  """
  attr :field, :string, required: true, doc: "field name to sort by"
  attr :current_sort, :string, default: nil, doc: "currently sorted field"
  attr :current_order, :string, default: nil, doc: "current sort order (asc/desc)"
  attr :label, :string, required: true, doc: "header label"
  attr :phx_click, :string, default: "sort", doc: "event name for sorting"
  attr :class, :string, default: ""

  def sortable_header(assigns) do
    is_active = assigns.current_sort == assigns.field
    order = if is_active, do: assigns.current_order, else: nil
    next_order = get_next_order(order)

    assigns =
      assigns
      |> assign(:is_active, is_active)
      |> assign(:next_order, next_order)

    ~H"""
    <th
      class={[
        "px-4 py-3 text-left text-xs font-semibold uppercase tracking-wide text-base-content/70 cursor-pointer select-none rounded-md hover:bg-base-200/50 hover:text-base-content focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/40 transition-colors",
        @class
      ]}
      phx-click={@phx_click}
      phx-value-field={@field}
      phx-value-order={@next_order}
    >
      <div class="flex items-center gap-2">
        <span>{@label}</span>
        <div class="flex flex-col">
          <.icon
            name="hero-chevron-up"
            class={
              if(@is_active && @current_order == "asc",
                do: "w-3 h-3 transition-colors text-primary",
                else: "w-3 h-3 transition-colors text-base-content/30"
              )
            }
          />
          <.icon
            name="hero-chevron-down"
            class={
              if(@is_active && @current_order == "desc",
                do: "w-3 h-3 -mt-1.5 transition-colors text-primary",
                else: "w-3 h-3 -mt-1.5 transition-colors text-base-content/30"
              )
            }
          />
        </div>
      </div>
    </th>
    """
  end

  defp get_next_order(nil), do: "asc"
  defp get_next_order("asc"), do: "desc"
  defp get_next_order("desc"), do: "asc"
  defp get_next_order(_), do: "asc"

  @doc """
  Renders a pagination component.

  ## Examples

      <.pagination
        page={@page}
        page_size={@page_size}
        total={@total}
        path={~p"/admin/campaigns"}
      />
  """
  attr :page, :integer, required: true, doc: "current page number (1-based)"
  attr :page_size, :integer, required: true, doc: "number of items per page"
  attr :total, :integer, required: true, doc: "total number of items"
  attr :path, :string, required: true, doc: "base path for pagination links"
  attr :params, :map, default: %{}, doc: "additional query parameters to preserve"
  attr :class, :string, default: ""

  def pagination(assigns) do
    total_pages = if assigns.page_size > 0, do: ceil(assigns.total / assigns.page_size), else: 1
    page = assigns.page

    assigns =
      assigns
      |> assign(:total_pages, total_pages)
      |> assign(:show_pagination?, total_pages > 1)
      |> assign(:prev_page, if(page > 1, do: page - 1, else: nil))
      |> assign(:next_page, if(page < total_pages, do: page + 1, else: nil))
      |> assign(:page_numbers, calculate_page_numbers(page, total_pages))

    ~H"""
    <div
      :if={@show_pagination?}
      class={["flex flex-col sm:flex-row items-center justify-between gap-4 mt-6", @class]}
    >
      <div class="flex items-center gap-2 text-sm text-slate-600">
        <span>顯示</span>
        <select
          phx-change="change_page_size"
          name="page_size"
          value={@page_size}
          class="rounded-lg border border-slate-200 px-2 py-1 text-sm focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
        >
          <option value="10">10</option>
          <option value="20">20</option>
          <option value="50">50</option>
          <option value="100">100</option>
        </select>
        <span>條，共 {@total} 條記錄</span>
      </div>

      <div class="flex items-center gap-1">
        <.link
          :if={@prev_page}
          patch={build_pagination_path(@path, @prev_page, @page_size, @params)}
          class="inline-flex items-center justify-center rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <.icon name="hero-chevron-left" class="w-4 h-4" />
        </.link>
        <button
          :if={!@prev_page}
          disabled
          class="inline-flex items-center justify-center rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-300 cursor-not-allowed"
        >
          <.icon name="hero-chevron-left" class="w-4 h-4" />
        </button>

        <div class="flex items-center gap-1">
          <button
            :for={page_num <- @page_numbers}
            :if={page_num != :ellipsis}
            type="button"
            phx-click="go_to_page"
            phx-value-page={page_num}
            class={[
              "inline-flex items-center justify-center rounded-lg border px-3 py-2 text-sm font-semibold transition-colors",
              if page_num == @page do
                "border-indigo-500 bg-indigo-50 text-indigo-700"
              else
                "border-slate-200 bg-white text-slate-700 hover:bg-slate-50"
              end
            ]}
          >
            {page_num}
          </button>
          <span
            :for={page_num <- @page_numbers}
            :if={page_num == :ellipsis}
            class="px-2 text-slate-400"
          >
            ...
          </span>
        </div>

        <.link
          :if={@next_page}
          patch={build_pagination_path(@path, @next_page, @page_size, @params)}
          class="inline-flex items-center justify-center rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <.icon name="hero-chevron-right" class="w-4 h-4" />
        </.link>
        <button
          :if={!@next_page}
          disabled
          class="inline-flex items-center justify-center rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-300 cursor-not-allowed"
        >
          <.icon name="hero-chevron-right" class="w-4 h-4" />
        </button>
      </div>
    </div>
    """
  end

  defp calculate_page_numbers(current_page, total_pages) do
    cond do
      total_pages <= 7 ->
        # Show all pages if 7 or fewer
        1..total_pages |> Enum.to_list()

      current_page <= 4 ->
        # Show first 5 pages, ellipsis, last page
        [1, 2, 3, 4, 5, :ellipsis, total_pages]

      current_page >= total_pages - 3 ->
        # Show first page, ellipsis, last 5 pages
        [
          1,
          :ellipsis,
          total_pages - 4,
          total_pages - 3,
          total_pages - 2,
          total_pages - 1,
          total_pages
        ]

      true ->
        # Show first page, ellipsis, current-1, current, current+1, ellipsis, last page
        [1, :ellipsis, current_page - 1, current_page, current_page + 1, :ellipsis, total_pages]
    end
  end

  defp build_pagination_path(path, page, page_size, params) do
    query_params =
      params
      |> Map.put("page", Integer.to_string(page))
      |> Map.put("page_size", Integer.to_string(page_size))
      |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
      |> Map.new()

    "#{path}?#{URI.encode_query(query_params)}"
  end
end
