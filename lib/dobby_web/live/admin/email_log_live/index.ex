defmodule DobbyWeb.Admin.EmailLogLive.Index do
  use DobbyWeb, :live_view

  alias Dobby.Emails
  alias Dobby.Campaigns
  alias DobbyWeb.LiveViewHelpers

  @default_filters %{
    status: "all",
    campaign_id: "all",
    search: ""
  }

  @impl true
  def mount(_params, _session, socket) do
    campaigns_result = Campaigns.list_campaigns(%{page: 1, page_size: 1000})

    {:ok,
     socket
     |> assign(:page_title, "Email Logs")
     |> assign(:email_logs, [])
     |> assign(:filters, @default_filters)
     |> assign(:page, 1)
     |> assign(:page_size, 20)
     |> assign(:sort_by, "inserted_at")
     |> assign(:sort_order, "desc")
     |> assign(:campaigns, campaigns_result.items)
     |> assign(:stats, %{total: 0, sent: 0, failed: 0})
     |> assign(:selected_log, nil)
     |> load_email_logs()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = parse_filters(params)
    page = LiveViewHelpers.parse_integer(params["page"], socket.assigns[:page] || 1)

    page_size =
      LiveViewHelpers.parse_integer(params["page_size"], socket.assigns[:page_size] || 20)

    sort_by = params["sort_by"] || socket.assigns[:sort_by] || "inserted_at"
    sort_order = params["sort_order"] || socket.assigns[:sort_order] || "desc"

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, page)
     |> assign(:page_size, page_size)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> load_email_logs()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    # Update filters based on what was sent in the form
    # params will contain the form field name and value, e.g. %{"status" => "sent"} or %{"campaign_id" => "123"}
    # Debug: log the received params
    require Logger
    Logger.debug("EmailLogLive filter event received: #{inspect(params)}")

    filters =
      socket.assigns.filters
      |> update_filter_if_present(params, "status")
      |> update_filter_if_present(params, "campaign_id")

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> load_email_logs()
     |> push_patch(to: build_filter_path(socket, filters, 1, socket.assigns.page_size))}
  end

  def handle_event("search", %{"search" => search}, socket) do
    filters = Map.put(socket.assigns.filters, :search, search)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> load_email_logs()
     |> push_patch(to: build_filter_path(socket, filters, 1, socket.assigns.page_size))}
  end

  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    page_size = LiveViewHelpers.parse_integer(page_size, 20)

    {:noreply,
     socket
     |> assign(:page_size, page_size)
     |> assign(:page, 1)
     |> load_email_logs()}
  end

  def handle_event("go_to_page", %{"page" => page}, socket) do
    page = LiveViewHelpers.parse_integer(page, 1)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_email_logs()}
  end

  def handle_event("sort", %{"field" => field, "order" => order}, socket) do
    {:noreply,
     socket
     |> assign(:sort_by, field)
     |> assign(:sort_order, order)
     |> assign(:page, 1)
     |> load_email_logs()}
  end

  def handle_event("view_log", %{"id" => id}, socket) do
    log = Emails.get_email_log!(id)
    {:noreply, assign(socket, :selected_log, log)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :selected_log, nil)}
  end

  defp update_filter_if_present(filters, params, key) when is_binary(key) do
    case Map.get(params, key) do
      nil ->
        filters

      value when is_binary(value) ->
        Map.put(filters, String.to_atom(key), value)

      value ->
        # Handle non-string values
        Map.put(filters, String.to_atom(key), to_string(value))
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :admin, current_nav: :email_logs}}>
      <.page_container>
        <.page_header title="郵件發送歷史" subtitle="查看所有郵件發送歷史記錄" />
        
    <!-- Stats Cards -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <.card class="shadow-none border-base-300 bg-base-100/80">
            <p class="text-sm text-base-content/60 mb-2">總發送數</p>
            <p class="text-3xl font-semibold">{@stats.total}</p>
          </.card>
          <.card class="shadow-none border border-success/40 bg-success/10">
            <p class="text-sm text-success mb-2">成功</p>
            <p class="text-3xl font-bold text-success">{@stats.sent}</p>
          </.card>
          <.card class="shadow-none border border-error/40 bg-error/10">
            <p class="text-sm text-error mb-2">失敗</p>
            <p class="text-3xl font-bold text-error">{@stats.failed}</p>
          </.card>
        </div>
        
    <!-- Filters -->
        <.card class="p-4 shadow-none bg-base-100/80 border-base-300">
          <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label class="block text-sm font-semibold text-base-content/70 mb-2">狀態</label>
              <.select
                name="status"
                value={@filters.status}
                options={[{"all", "全部"}, {"sent", "成功"}, {"failed", "失敗"}, {"pending", "待發送"}]}
                phx-change="filter"
              />
            </div>
            <div>
              <label class="block text-sm font-semibold text-base-content/70 mb-2">活動</label>
              <.select
                name="campaign_id"
                value={@filters.campaign_id}
                options={
                  if Enum.empty?(@campaigns) do
                    [{"all", "無活動"}]
                  else
                    [{"all", "全部活動"}] ++ Enum.map(@campaigns, fn c -> {c.id, c.name} end)
                  end
                }
                phx-change="filter"
                placeholder={if Enum.empty?(@campaigns), do: "無活動", else: "選擇活動"}
              />
            </div>
            <div>
              <label class="block text-sm font-semibold text-base-content/70 mb-2">搜尋</label>
              <.search_input
                name="search"
                value={@filters.search}
                placeholder="搜尋收件人或主題..."
                phx_change="search"
                phx_debounce="300"
                class="mb-0"
              />
            </div>
          </div>
        </.card>
        
    <!-- Email Logs Table -->
        <.card class="overflow-hidden p-0">
          <table class="min-w-full divide-y divide-base-300 bg-base-100 text-base-content">
            <thead class="bg-base-200/80 text-xs font-semibold uppercase tracking-[0.2em] text-base-content/70">
              <tr>
                <.sortable_header
                  field="inserted_at"
                  current_sort={@sort_by}
                  current_order={@sort_order}
                  label="發送時間"
                />
                <.sortable_header
                  field="to_email"
                  current_sort={@sort_by}
                  current_order={@sort_order}
                  label="收件人"
                />
                <th class="px-4 py-3 text-left">活動</th>
                <th class="px-4 py-3 text-left">模板</th>
                <.sortable_header
                  field="subject"
                  current_sort={@sort_by}
                  current_order={@sort_order}
                  label="主題"
                />
                <.sortable_header
                  field="status"
                  current_sort={@sort_by}
                  current_order={@sort_order}
                  label="狀態"
                />
                <th class="px-4 py-3 text-right">操作</th>
              </tr>
            </thead>
            <tbody class="bg-base-100 divide-y divide-base-200 text-sm">
              <tr :for={log <- @email_logs} class="hover:bg-base-200/50 transition-colors">
                <td class="px-4 py-4 text-base-content/70">
                  {format_datetime(log.sent_at || log.inserted_at)}
                </td>
                <td class="px-4 py-4">{log.to_email}</td>
                <td class="px-4 py-4">
                  {if log.campaign, do: log.campaign.name, else: "—"}
                </td>
                <td class="px-4 py-4">
                  {if log.email_template, do: log.email_template.name, else: "—"}
                </td>
                <td class="px-4 py-4">{log.subject}</td>
                <td class="px-4 py-4 text-base-content">
                  <.badge variant={status_badge_variant(log.status)}>
                    {status_label(log.status)}
                  </.badge>
                </td>
                <td class="px-4 py-4 text-right">
                  <button
                    phx-click="view_log"
                    phx-value-id={log.id}
                    class="text-primary hover:text-primary/80 text-sm transition-colors"
                  >
                    查看詳情
                  </button>
                </td>
              </tr>
              <tr :if={Enum.empty?(@email_logs)}>
                <td colspan="7" class="px-4 py-12 text-center text-base-content/50 text-sm">
                  目前沒有符合條件的郵件記錄
                </td>
              </tr>
            </tbody>
          </table>
        </.card>

        <.pagination
          :if={!Enum.empty?(@email_logs)}
          page={@email_logs_page}
          page_size={@email_logs_page_size}
          total={@email_logs_total}
          path={~p"/admin/email-logs"}
          params={
            %{
              "status" => if(@filters.status == "all", do: nil, else: @filters.status),
              "campaign_id" => if(@filters.campaign_id == "all", do: nil, else: @filters.campaign_id),
              "search" => if(@filters.search == "", do: nil, else: @filters.search),
              "sort_by" => @sort_by,
              "sort_order" => @sort_order
            }
          }
        />
        
    <!-- Modal for viewing email details -->
        <div
          :if={@selected_log}
          class="fixed inset-0 z-50 flex items-center justify-center bg-base-content/60 backdrop-blur-sm"
        >
          <div class="bg-base-100 text-base-content rounded-2xl shadow-2xl shadow-primary/20 w-full max-w-3xl max-h-[90vh] overflow-y-auto p-6">
            <div class="flex items-center justify-between mb-6">
              <h2 class="text-2xl font-semibold">郵件詳情</h2>
              <button
                phx-click="close_modal"
                class="text-base-content/50 hover:text-base-content/80 transition-colors"
              >
                <.icon name="hero-x-mark" class="h-6 w-6" />
              </button>
            </div>

            <div class="space-y-4">
              <div>
                <p class="text-sm font-semibold text-base-content/70">收件人</p>
                <p class="text-sm">{@selected_log.to_email}</p>
              </div>
              <div>
                <p class="text-sm font-semibold text-base-content/70">主題</p>
                <p class="text-sm">{@selected_log.subject}</p>
              </div>
              <div>
                <p class="text-sm font-semibold text-base-content/70">狀態</p>
                <.badge variant={status_badge_variant(@selected_log.status)} class="mt-1">
                  {status_label(@selected_log.status)}
                </.badge>
                <p :if={@selected_log.error_message} class="text-sm text-error mt-2">
                  錯誤：{@selected_log.error_message}
                </p>
              </div>
              <div>
                <p class="text-sm font-semibold text-base-content/70">郵件內容</p>
                <.card class="mt-2 p-4 bg-base-100/90 border-base-300 shadow-none">
                  <div class="prose max-w-none text-base-content">
                    {Phoenix.HTML.raw(@selected_log.html_content || "")}
                  </div>
                </.card>
              </div>
            </div>
          </div>
        </div>
      </.page_container>
    </Layouts.app>
    """
  end

  defp load_email_logs(socket) do
    opts =
      build_query_opts(socket.assigns.filters)
      |> Keyword.put(:page, socket.assigns.page)
      |> Keyword.put(:page_size, socket.assigns.page_size)
      |> Keyword.put(:sort_by, socket.assigns.sort_by)
      |> Keyword.put(:sort_order, socket.assigns.sort_order)

    result = Emails.list_all_email_logs(opts)
    stats = Emails.get_email_log_stats(build_query_opts(socket.assigns.filters))

    socket
    |> assign(:email_logs, result.items)
    |> assign(:email_logs_total, result.total)
    |> assign(:email_logs_page, result.page)
    |> assign(:email_logs_page_size, result.page_size)
    |> assign(:stats, stats)
  end

  defp parse_filters(params) do
    %{
      status: Map.get(params, "status", "all"),
      campaign_id: Map.get(params, "campaign_id", "all"),
      search: Map.get(params, "search", "")
    }
  end

  defp build_query_opts(filters) do
    [
      status: if(filters.status == "all", do: nil, else: filters.status),
      campaign_id: if(filters.campaign_id == "all", do: nil, else: filters.campaign_id),
      search: if(filters.search == "", do: nil, else: filters.search)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp build_filter_path(socket, filters, page, page_size) do
    params =
      %{
        "page" => Integer.to_string(page),
        "page_size" => Integer.to_string(page_size),
        "status" => if(filters.status == "all", do: nil, else: filters.status),
        "campaign_id" => if(filters.campaign_id == "all", do: nil, else: filters.campaign_id),
        "search" => if(filters.search == "", do: nil, else: filters.search),
        "sort_by" => socket.assigns.sort_by,
        "sort_order" => socket.assigns.sort_order
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
      |> Map.new()

    ~p"/admin/email-logs?#{params}"
  end

  defp status_badge_variant("sent"), do: "success"
  defp status_badge_variant("failed"), do: "error"
  defp status_badge_variant("pending"), do: "warning"
  defp status_badge_variant(_), do: "default"

  defp status_label("sent"), do: "成功"
  defp status_label("failed"), do: "失敗"
  defp status_label("pending"), do: "待發送"
  defp status_label(_), do: "未知"

  defp format_datetime(nil), do: "—"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y/%m/%d %H:%M")
end
