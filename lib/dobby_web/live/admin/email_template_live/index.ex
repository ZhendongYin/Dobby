defmodule DobbyWeb.Admin.EmailTemplateLive.Index do
  use DobbyWeb, :live_view

  alias Dobby.Emails
  alias Dobby.Emails.EmailTemplate
  alias DobbyWeb.LiveViewHelpers

  @variable_catalog [
    %{label: "玩家姓名", variable: "user_name", sample: "王小明"},
    %{label: "活動名稱", variable: "campaign_name", sample: "夏日刮刮樂"},
    %{label: "獎品名稱", variable: "prize_name", sample: "豪華旅行組"},
    %{label: "獎品描述", variable: "prize_description", sample: "含雙人來回機票與五星飯店住宿"},
    %{label: "兌換說明", variable: "redemption_guide", sample: "請於 7 天內回覆此信件提供寄送資訊"},
    %{label: "交易序號", variable: "transaction_number", sample: "TX-928341"},
    %{label: "虛擬序號", variable: "virtual_code", sample: "ABCD-1234"},
    %{label: "支援信箱", variable: "support_email", sample: "support@example.com"},
    %{label: "到期日期", variable: "expiry_date", sample: "2025 年 1 月 15 日"}
  ]

  @preview_sample Enum.into(@variable_catalog, %{}, fn %{variable: v, sample: s} -> {v, s} end)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :admin, current_nav: :email_templates}}>
      <.page_container>
        <%= if assigns.live_action in [:new, :edit] do %>
          <.admin_form_shell
            back_href={~p"/admin/email-templates"}
            eyebrow="Email Template"
            title={@page_title}
            subtitle="維護郵件通知模板，確保所有活動與獎品的對外溝通語氣一致。"
          >
            <:form>
              <.form
                for={@template_form}
                phx-submit="save_template"
                phx-change="validate_template"
                class="space-y-5"
              >
                <.input field={@template_form[:name]} type="text" label="模板名稱" required />
                <.input field={@template_form[:subject]} type="text" label="郵件主旨" required />

                <div class="space-y-3">
                  <div class="flex flex-wrap items-center justify-between gap-3">
                    <label class="text-sm font-semibold text-base-content">HTML 內容</label>
                    <div class="flex flex-wrap gap-2 text-xs text-base-content/60">
                      <span>可插入變數：</span>
                      <button
                        :for={variable <- @variable_catalog}
                        type="button"
                        phx-click="insert_variable"
                        phx-value-variable={variable.variable}
                        class="inline-flex items-center gap-1 rounded-full border border-base-300 px-2 py-0.5 text-[11px] font-semibold text-base-content/70 hover:bg-base-200/50 transition-colors"
                      >
                        {"{{#{variable.variable}}}"}
                      </button>
                    </div>
                  </div>

                  <div
                    id="email-editor-container"
                    phx-hook="EmailEditor"
                    phx-update="ignore"
                    data-initial-content={@template_form[:html_content].value || ""}
                    class="rounded-xl border border-base-300 bg-base-100/95 shadow-sm"
                  >
                    <div id="email-editor" class="min-h-[320px]"></div>
                    <input
                      type="hidden"
                      id="html-content-input"
                      name="email_template[html_content]"
                      value={@template_form[:html_content].value}
                    />
                    <textarea
                      id="text-content-input"
                      name="email_template[text_content]"
                      class="hidden"
                    ><%= @template_form[:text_content].value || "" %></textarea>
                  </div>
                  <p class="text-xs text-base-content/60">
                    使用 Quill 編輯器撰寫郵件內容，點擊上方變數可快速插入佔位符。
                  </p>
                  <%= for {msg, _} <- @template_form[:html_content].errors do %>
                    <p class="text-xs text-rose-600">{msg}</p>
                  <% end %>
                </div>

                <div class="flex justify-end gap-3 pt-4 border-t border-base-300">
                  <.secondary_button navigate={~p"/admin/email-templates"}>
                    取消
                  </.secondary_button>
                  <.primary_button type="submit">
                    儲存模板
                  </.primary_button>
                </div>
              </.form>
            </:form>

            <:sidebar>
              <div class="space-y-6">
                <div class="space-y-4">
                  <p class="text-xs uppercase tracking-[0.3em] text-base-content/50">預覽</p>
                  <div class="rounded-2xl border border-base-300 bg-base-100/90 p-4 shadow-sm min-h-[320px]">
                    <div class="text-xs uppercase tracking-[0.3em] text-base-content/50 mb-3">
                      範例預覽（以測試資料套版）
                    </div>
                    <div class="prose prose-slate dark:prose-invert max-w-none">
                      {Phoenix.HTML.raw(@preview_html || "")}
                    </div>
                  </div>
                </div>

                <div class="space-y-4">
                  <p class="text-xs uppercase tracking-[0.3em] text-base-content/50">變數對照</p>
                  <div class="space-y-3">
                    <div
                      :for={variable <- @variable_catalog}
                      class="rounded-2xl border border-base-300 bg-base-100/90 p-4 shadow-sm"
                    >
                      <p class="text-sm font-semibold text-base-content">{variable.label}</p>
                      <p class="text-xs text-base-content/70">變數：{"{{#{variable.variable}}}"}</p>
                      <p class="text-xs text-base-content/60 mt-1">範例：{variable.sample}</p>
                    </div>
                  </div>
                </div>
              </div>
            </:sidebar>
          </.admin_form_shell>
        <% else %>
          <!-- Index Page -->
          <div class="flex flex-wrap items-center justify-between gap-4 mb-8">
            <.page_header
              title="郵件模板"
              subtitle="管理所有通知版型，可在活動或獎品中選擇使用。"
            />
            <.primary_button navigate={~p"/admin/email-templates/new"}>
              <.icon name="hero-plus" class="h-4 w-4" /> 新增模板
            </.primary_button>
          </div>

          <div class="mb-6">
            <.search_input
              name="search"
              value={@search}
              placeholder="搜尋模板名稱或主旨..."
              phx_change="search"
            />
          </div>

          <.card class="overflow-hidden">
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-base-300 bg-base-100 text-base-content">
                <thead class="bg-base-200/80">
                  <tr class="text-left text-xs font-semibold uppercase tracking-[0.2em] text-base-content/70">
                    <.sortable_header
                      field="name"
                      current_sort={@sort_by}
                      current_order={@sort_order}
                      label="模板名稱"
                    />
                    <.sortable_header
                      field="subject"
                      current_sort={@sort_by}
                      current_order={@sort_order}
                      label="主旨"
                    />
                    <.sortable_header
                      field="updated_at"
                      current_sort={@sort_by}
                      current_order={@sort_order}
                      label="最新更新"
                    />
                    <th class="px-4 py-3 text-right">管理</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-200 bg-base-100">
                  <tr
                    :for={template <- @templates}
                    id={"email-template-#{template.id}"}
                    class="hover:bg-base-200/50 transition-colors text-sm"
                  >
                    <td class="px-4 py-4">
                      <p class="font-semibold text-base-content">{template.name}</p>
                    </td>
                    <td class="px-4 py-4">
                      <p class="text-base-content/70 line-clamp-1">{template.subject}</p>
                    </td>
                    <td class="px-4 py-4 text-base-content/70">
                      {Calendar.strftime(template.updated_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="px-4 py-4 text-right">
                      <div class="inline-flex items-center gap-3 text-sm">
                        <.link
                          navigate={~p"/admin/email-templates/#{template.id}/edit"}
                          class="text-primary hover:text-primary/80 transition-colors"
                        >
                          編輯
                        </.link>
                        <button
                          type="button"
                          phx-click="delete_template"
                          phx-value-id={template.id}
                          data-confirm="確定刪除此模板？"
                          class="text-base-content/40 hover:text-error transition-colors"
                        >
                          刪除
                        </button>
                      </div>
                    </td>
                  </tr>
                  <tr :if={Enum.empty?(@templates)}>
                    <td colspan="4" class="px-4 py-12 text-center text-base-content/50 text-sm">
                      尚未建立任何模板，點擊右上角的「新增模板」開始建立。
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.card>

          <.pagination
            :if={!Enum.empty?(@templates)}
            page={@templates_page}
            page_size={@templates_page_size}
            total={@templates_total}
            path={~p"/admin/email-templates"}
            params={
              %{
                "search" => @search,
                "sort_by" => @sort_by,
                "sort_order" => @sort_order
              }
            }
          />
        <% end %>
      </.page_container>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign_default_state()
     |> assign(:page, 1)
     |> assign(:page_size, 20)
     |> assign(:sort_by, "inserted_at")
     |> assign(:sort_order, "desc")
     |> load_templates()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    template = %EmailTemplate{
      html_content: default_html_content(),
      text_content: default_text_content()
    }

    socket
    |> assign(:page_title, "新增郵件模板")
    |> assign(:current_template, template)
    |> assign(:template_form, template_form(template))
    |> assign(:preview_html, render_preview(template.html_content))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    template = Emails.get_email_template!(id)

    socket
    |> assign(:page_title, "編輯 · #{template.name}")
    |> assign(:current_template, template)
    |> assign(:template_form, template_form(template))
    |> assign(:preview_html, render_preview(template.html_content))
  end

  defp apply_action(socket, :index, params) do
    page = LiveViewHelpers.parse_integer(params["page"], socket.assigns[:page] || 1)

    page_size =
      LiveViewHelpers.parse_integer(params["page_size"], socket.assigns[:page_size] || 20)

    sort_by = params["sort_by"] || socket.assigns[:sort_by] || "inserted_at"
    sort_order = params["sort_order"] || socket.assigns[:sort_order] || "desc"
    search = params["search"] || socket.assigns[:search] || ""

    socket
    |> assign(:page_title, "郵件模板")
    |> assign(:page, page)
    |> assign(:page_size, page_size)
    |> assign(:sort_by, sort_by)
    |> assign(:sort_order, sort_order)
    |> assign(:search, search)
    |> load_templates()
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:page, 1)
     |> load_templates()}
  end

  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    page_size = LiveViewHelpers.parse_integer(page_size, 20)

    {:noreply,
     socket
     |> assign(:page_size, page_size)
     |> assign(:page, 1)
     |> load_templates()}
  end

  def handle_event("go_to_page", %{"page" => page}, socket) do
    page = LiveViewHelpers.parse_integer(page, 1)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_templates()}
  end

  def handle_event("validate_template", %{"email_template" => params}, socket) do
    form =
      socket.assigns.current_template
      |> Emails.change_email_template(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply,
     socket
     |> assign(:template_form, form)
     |> assign(:preview_html, render_preview(params["html_content"]))}
  end

  def handle_event("save_template", %{"email_template" => params}, socket) do
    save_fun =
      if socket.assigns.live_action == :new do
        fn -> Emails.create_email_template(params) end
      else
        fn -> Emails.update_email_template(socket.assigns.current_template, params) end
      end

    case save_fun.() do
      {:ok, _template} ->
        {:noreply,
         socket
         |> put_flash(:info, "郵件模板已儲存")
         |> push_navigate(to: ~p"/admin/email-templates")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:template_form, to_form(changeset))
         |> assign(:preview_html, render_preview(changeset.changes[:html_content] || ""))}
    end
  end

  def handle_event("delete_template", %{"id" => id}, socket) do
    template = Emails.get_email_template!(id)

    case Emails.delete_email_template(template) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "模板已刪除")
         |> load_templates()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "無法刪除此模板")}
    end
  end

  def handle_event("editor-update", %{"html_content" => html}, socket) do
    {:noreply, assign(socket, :preview_html, render_preview(html))}
  end

  def handle_event("insert_variable", %{"variable" => variable}, socket) do
    {:noreply, push_event(socket, "insert-variable", %{variable: variable})}
  end

  defp assign_default_state(socket) do
    template = %EmailTemplate{
      html_content: default_html_content(),
      text_content: default_text_content()
    }

    socket
    |> assign(:templates, [])
    |> assign(:search, "")
    |> assign(:current_template, template)
    |> assign(:template_form, template_form(template))
    |> assign(:preview_html, render_preview(template.html_content))
    |> assign(:variable_catalog, @variable_catalog)
  end

  defp load_templates(socket) do
    filters = %{
      search: socket.assigns.search,
      page: socket.assigns.page,
      page_size: socket.assigns.page_size,
      sort_by: socket.assigns.sort_by,
      sort_order: socket.assigns.sort_order
    }

    result = Emails.list_global_templates(filters)

    socket
    |> assign(:templates, result.items)
    |> assign(:templates_total, result.total)
    |> assign(:templates_page, result.page)
    |> assign(:templates_page_size, result.page_size)
  end

  defp template_form(template) do
    template
    |> Emails.change_email_template(%{})
    |> to_form()
  end

  defp render_preview(nil), do: render_preview("")

  defp render_preview(html) do
    Enum.reduce(@preview_sample, html || "", fn {key, value}, acc ->
      acc
      |> String.replace("{{#{key}}}", value || "")
      |> String.replace("{#{key}}", value || "")
    end)
  end

  defp default_html_content do
    """
    <h2>親愛的 {{user_name}} 您好：</h2>
    <p>恭喜您在「{{campaign_name}}」活動中抽中 <strong>{{prize_name}}</strong>！🎉</p>
    <p>{{prize_description}}</p>
    <p>{{redemption_guide}}</p>
    <p style="margin-top: 24px;">如有任何問題，歡迎來信 {{support_email}}，我們會儘速協助您。</p>
    <p>祝您一切順心，活動團隊敬上</p>
    """
  end

  defp default_text_content do
    """
    親愛的 {{user_name}} 您好：

    恭喜您在 {{campaign_name}} 活動中抽中 {{prize_name}}！
    {{prize_description}}

    {{redemption_guide}}

    有問題可回覆此信或寫信至 {{support_email}}。

    活動團隊敬上
    """
    |> String.trim()
  end
end
