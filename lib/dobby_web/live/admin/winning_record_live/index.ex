defmodule DobbyWeb.Admin.WinningRecordLive.Index do
  use DobbyWeb, :live_view

  alias Dobby.Lottery
  alias Dobby.Campaigns
  alias Dobby.Emails
  alias DobbyWeb.LiveViewHelpers

  @status_options [
    {"All statuses", "all"},
    {"Pending Submit", "pending_submit"},
    {"Pending Process", "pending_process"},
    {"Fulfilled", "fulfilled"},
    {"Expired", "expired"}
  ]

  @impl true
  def mount(%{"id" => campaign_id}, _session, socket) do
    campaign = Campaigns.get_campaign!(campaign_id)

    {:ok,
     socket
     |> assign(:campaign, campaign)
     |> assign(:status_filter, "all")
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:page_size, 20)
     |> assign(:sort_by, "inserted_at")
     |> assign(:sort_order, "desc")
     |> assign(:status_options, @status_options)
     |> assign(:selected_record, nil)
     |> assign(:show_modal?, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:page_title, "#{campaign.name} · Winning Records")
     |> load_records()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    page = LiveViewHelpers.parse_integer(params["page"], socket.assigns[:page] || 1)

    page_size =
      LiveViewHelpers.parse_integer(params["page_size"], socket.assigns[:page_size] || 20)

    search = params["search"] || socket.assigns[:search] || ""
    status = params["status"] || socket.assigns[:status_filter] || "all"
    sort_by = params["sort_by"] || socket.assigns[:sort_by] || "inserted_at"
    sort_order = params["sort_order"] || socket.assigns[:sort_order] || "desc"

    {:noreply,
     socket
     |> assign(:page, page)
     |> assign(:page_size, page_size)
     |> assign(:search, search)
     |> assign(:status_filter, status)
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> load_records()}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:page, 1)
     |> load_records()
     |> push_patch(to: current_path(socket, search: search))}
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:page, 1)
     |> load_records()
     |> push_patch(to: current_path(socket, status: status))}
  end

  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    page_size = LiveViewHelpers.parse_integer(page_size, 20)

    {:noreply,
     socket
     |> assign(:page_size, page_size)
     |> assign(:page, 1)
     |> load_records()
     |> push_patch(to: current_path(socket, page: 1, page_size: page_size))}
  end

  def handle_event("go_to_page", %{"page" => page}, socket) do
    page = LiveViewHelpers.parse_integer(page, 1)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_records()
     |> push_patch(to: current_path(socket, page: page, page_size: socket.assigns.page_size))}
  end

  def handle_event("sort", %{"field" => field, "order" => order}, socket) do
    {:noreply,
     socket
     |> assign(:sort_by, field)
     |> assign(:sort_order, order)
     |> assign(:page, 1)
     |> load_records()
     |> push_patch(
       to:
         current_path(socket,
           page: 1,
           page_size: socket.assigns.page_size,
           sort_by: field,
           sort_order: order
         )
     )}
  end

  def handle_event("mark_status", %{"id" => id, "status" => status}, socket) do
    record = Enum.find(socket.assigns.records, &(&1.id == id))

    case Lottery.update_winning_record_status(record, status) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_records()
         |> put_flash(:info, "Status updated")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update status")}
    end
  end

  def handle_event("show_details", %{"id" => id}, socket) do
    record = Lottery.get_winning_record_with_details!(id)

    {:noreply,
     socket
     |> assign(:selected_record, record)
     |> assign(:show_modal?, true)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_modal?, false)
     |> assign(:selected_record, nil)}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected_ids =
      if MapSet.member?(socket.assigns.selected_ids, id) do
        MapSet.delete(socket.assigns.selected_ids, id)
      else
        MapSet.put(socket.assigns.selected_ids, id)
      end

    {:noreply, assign(socket, :selected_ids, selected_ids)}
  end

  @impl true
  def handle_event("select_all", _params, socket) do
    all_ids = socket.assigns.records |> Enum.map(& &1.id) |> MapSet.new()
    {:noreply, assign(socket, :selected_ids, all_ids)}
  end

  @impl true
  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected_ids, MapSet.new())}
  end

  @impl true
  def handle_event("bulk_update_status", %{"status" => status}, socket) do
    selected_ids = MapSet.to_list(socket.assigns.selected_ids)

    if Enum.empty?(selected_ids) do
      {:noreply, put_flash(socket, :error, "請先選擇要更新的記錄")}
    else
      results =
        Enum.map(selected_ids, fn id ->
          record = Enum.find(socket.assigns.records, &(&1.id == id))

          if record,
            do: Lottery.update_winning_record_status(record, status),
            else: {:error, :not_found}
        end)

      success_count = Enum.count(results, &match?({:ok, _}, &1))

      {:noreply,
       socket
       |> load_records()
       |> assign(:selected_ids, MapSet.new())
       |> put_flash(:info, "已更新 #{success_count} 筆記錄的狀態為 #{status_label(status)}")}
    end
  end

  @impl true
  def handle_event("resend_email", %{"id" => id}, socket) do
    record = Enum.find(socket.assigns.records, &(&1.id == id))

    if record && record.email do
      Task.start(fn ->
        case Emails.resend_winning_notification(record) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            require Logger
            Logger.error("Failed to resend email: #{inspect(reason)}")
        end
      end)

      {:noreply,
       socket
       |> load_records()
       |> put_flash(:info, "Email resend initiated. Please check the email status shortly.")}
    else
      {:noreply, put_flash(socket, :error, "Record not found or email address missing")}
    end
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    # Export all records, not just current page
    result =
      list_records(socket.assigns.campaign.id, %{
        "search" => socket.assigns.search,
        "status" => socket.assigns.status_filter,
        "page" => 1,
        "page_size" => 10000
      })

    rows =
      [["Name", "Email", "Phone", "Prize", "Status", "Transaction", "Inserted At"]] ++
        Enum.map(result.items, fn record ->
          [
            record.name || "-",
            record.email || "-",
            record.phone || "-",
            (record.prize && record.prize.name) || "-",
            status_label(record.status),
            (record.transaction_number && record.transaction_number.transaction_number) || "-",
            format_datetime(record.inserted_at)
          ]
        end)

    csv =
      rows
      |> Enum.map(fn row ->
        row
        |> Enum.map(&escape_csv/1)
        |> Enum.join(",")
      end)
      |> Enum.join("\n")

    {:noreply,
     socket
     |> push_event("download_csv", %{
       filename: "winning-records-#{Date.utc_today()}.csv",
       content: csv,
       content_type: "text/csv"
     })}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :admin, current_nav: :campaigns}}>
      <div
        id="winning-records"
        phx-hook="DownloadCSV"
        class="relative"
      >
        <.page_container>
          <.page_header
            title={@campaign.name}
            subtitle="Winning Records"
          />

          <.card class="space-y-4">
            <div class="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <form phx-change="search" class="flex-1" phx-debounce="400">
                <.input
                  type="text"
                  name="search"
                  value={@search}
                  placeholder="Search by email, name, or transaction code"
                  class="w-full"
                />
              </form>
              <div class="flex gap-3 flex-wrap md:flex-nowrap">
                <.select
                  name="status"
                  value={@status_filter}
                  options={@status_options}
                  phx-change="filter_status"
                  class="rounded-xl"
                />
                <div
                  :if={MapSet.size(@selected_ids) > 0}
                  class="flex gap-2 items-center rounded-md border border-indigo-300 bg-indigo-50 px-3 py-2"
                >
                  <span class="text-sm font-semibold text-indigo-700">
                    已選擇 {MapSet.size(@selected_ids)} 筆
                  </span>
                  <button
                    type="button"
                    phx-click="bulk_update_status"
                    phx-value-status="fulfilled"
                    class="text-xs font-semibold text-indigo-600 hover:text-indigo-800"
                  >
                    批量標記為已完成
                  </button>
                  <button
                    type="button"
                    phx-click="bulk_update_status"
                    phx-value-status="pending_process"
                    class="text-xs font-semibold text-indigo-600 hover:text-indigo-800"
                  >
                    批量標記為處理中
                  </button>
                  <button
                    type="button"
                    phx-click="deselect_all"
                    class="text-xs text-slate-500 hover:text-slate-700"
                  >
                    取消選擇
                  </button>
                </div>
                <.secondary_button phx-click="export_csv">
                  Export CSV
                </.secondary_button>
              </div>
            </div>

            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-base-300 bg-base-100 text-base-content">
                <thead class="bg-base-200/80 text-xs font-semibold uppercase tracking-[0.2em] text-base-content/70">
                  <tr>
                    <th class="px-4 py-3 text-left">
                      <input
                        type="checkbox"
                        phx-click="select_all"
                        checked={
                          MapSet.size(@selected_ids) == length(@records) && length(@records) > 0
                        }
                        class="rounded border-base-300 text-primary focus:ring-primary"
                      />
                    </th>
                    <.sortable_header
                      field="name"
                      current_sort={@sort_by}
                      current_order={@sort_order}
                      label="Winner"
                    />
                    <th class="px-4 py-3 text-left">
                      Prize
                    </th>
                    <.sortable_header
                      field="status"
                      current_sort={@sort_by}
                      current_order={@sort_order}
                      label="Status"
                    />
                    <.sortable_header
                      field="inserted_at"
                      current_sort={@sort_by}
                      current_order={@sort_order}
                      label="Submitted"
                    />
                    <th class="px-4 py-3 text-right">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-200 bg-base-100 text-sm">
                  <tr
                    :for={record <- @records}
                    id={"record-#{record.id}"}
                    class="hover:bg-base-200/50 transition-colors"
                  >
                    <td class="px-4 py-4">
                      <input
                        type="checkbox"
                        phx-click="toggle_select"
                        phx-value-id={record.id}
                        checked={MapSet.member?(@selected_ids, record.id)}
                        class="rounded border-base-300 text-primary focus:ring-primary"
                      />
                    </td>
                    <td class="px-4 py-4">
                      <p class="font-medium text-base-content">{record.name || "—"}</p>
                      <p class="text-base-content/70 text-xs">{record.email || "No email"}</p>
                      <p :if={record.transaction_number} class="text-base-content/50 text-xs">
                        Code: {record.transaction_number.transaction_number}
                      </p>
                    </td>
                    <td class="px-4 py-4 text-base-content">
                      <p class="font-medium">{record.prize && record.prize.name}</p>
                      <p class="text-xs text-base-content/70 capitalize">
                        {record.prize && record.prize.prize_type}
                      </p>
                    </td>
                    <td class="px-4 py-4">
                      <.badge variant={status_badge_variant(record.status)}>
                        {status_label(record.status)}
                      </.badge>
                    </td>
                    <td class="px-4 py-4 text-gray-500">
                      {format_datetime(record.inserted_at)}
                    </td>
                    <td class="px-4 py-4 text-right">
                      <div class="flex gap-2 justify-end">
                        <button
                          phx-click={JS.push("show_details", value: %{id: record.id})}
                          class="text-indigo-600 hover:text-indigo-900 text-sm font-semibold"
                        >
                          Details
                        </button>
                        <button
                          :if={record.email}
                          phx-click="resend_email"
                          phx-value-id={record.id}
                          class="text-emerald-600 hover:text-emerald-900 text-sm font-semibold"
                          title="重新發送郵件"
                        >
                          Resend Email
                        </button>
                        <button
                          :if={record.status != "fulfilled"}
                          phx-click="mark_status"
                          phx-value-id={record.id}
                          phx-value-status="fulfilled"
                          class="text-indigo-600 hover:text-indigo-900 text-sm font-semibold"
                        >
                          Mark Fulfilled
                        </button>
                        <button
                          :if={record.status != "pending_process"}
                          phx-click="mark_status"
                          phx-value-id={record.id}
                          phx-value-status="pending_process"
                          class="text-gray-500 hover:text-gray-700 text-sm"
                        >
                          Pending
                        </button>
                      </div>
                    </td>
                  </tr>
                  <tr :if={Enum.empty?(@records)}>
                    <td colspan="6" class="px-4 py-12 text-center text-slate-500 text-sm">
                      No winning records found.
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <.pagination
              :if={!Enum.empty?(@records)}
              page={@records_page}
              page_size={@records_page_size}
              total={@records_total}
              path={~p"/admin/campaigns/#{@campaign.id}/winning-records"}
              params={
                %{
                  "search" => @search,
                  "status" => @status_filter,
                  "sort_by" => @sort_by,
                  "sort_order" => @sort_order
                }
              }
            />
          </.card>
          <%= if @show_modal? && @selected_record do %>
            <div class="fixed inset-0 z-30 bg-slate-900/70 backdrop-blur-sm" />
            <div class="fixed inset-0 z-40 flex items-center justify-center p-6">
              <div class="w-full max-w-2xl rounded-3xl bg-white shadow-2xl ring-1 ring-black/5 p-6 lg:p-8 space-y-6">
                <div>
                  <p class="text-sm uppercase tracking-[0.35em] text-slate-400 mb-2">
                    Winning Record
                  </p>
                  <h2 class="text-2xl font-semibold text-slate-900">
                    {@selected_record.prize && @selected_record.prize.name}
                  </h2>
                  <p class="text-sm text-slate-500">
                    Transaction code: {@selected_record.transaction_number &&
                      @selected_record.transaction_number.transaction_number}
                  </p>
                </div>

                <div class="grid gap-4 sm:grid-cols-2">
                  <.card class="p-4">
                    <p class="text-xs uppercase tracking-[0.35em] text-slate-400 mb-2">Winner</p>
                    <p class="text-lg font-medium text-slate-900">{@selected_record.name || "-"}</p>
                    <p class="text-sm text-slate-500">{@selected_record.email || "-"}</p>
                  </.card>
                  <.card class="p-4">
                    <p class="text-xs uppercase tracking-[0.35em] text-slate-400 mb-2">Status</p>
                    <.badge variant={status_badge_variant(@selected_record.status)}>
                      {status_label(@selected_record.status)}
                    </.badge>
                  </.card>
                </div>

                <.card class="p-4 space-y-3 text-sm text-slate-600">
                  <div>
                    <p class="text-xs uppercase tracking-[0.35em] text-slate-400">Phone</p>
                    <p>{@selected_record.phone || "-"}</p>
                  </div>
                  <div>
                    <p class="text-xs uppercase tracking-[0.35em] text-slate-400">Address</p>
                    <p>{@selected_record.address || "N/A"}</p>
                  </div>
                  <div>
                    <p class="text-xs uppercase tracking-[0.35em] text-slate-400">Virtual Code</p>
                    <p>{@selected_record.virtual_code || "-"}</p>
                  </div>
                </.card>

                <div class="flex justify-end">
                  <.secondary_button phx-click="close_modal">
                    Close
                  </.secondary_button>
                </div>
              </div>
            </div>
          <% end %>
        </.page_container>
      </div>
    </Layouts.app>
    """
  end

  defp load_records(socket) do
    opts = %{
      "search" => socket.assigns.search,
      "status" => socket.assigns.status_filter,
      "page" => socket.assigns.page,
      "page_size" => socket.assigns.page_size,
      "sort_by" => socket.assigns.sort_by,
      "sort_order" => socket.assigns.sort_order
    }

    result = Lottery.list_winning_records(socket.assigns.campaign.id, opts)

    socket
    |> assign(:records, result.items)
    |> assign(:records_total, result.total)
    |> assign(:records_page, result.page)
    |> assign(:records_page_size, result.page_size)
  end

  defp list_records(campaign_id, params) do
    Lottery.list_winning_records(campaign_id, params)
  end

  defp current_path(socket, overrides) do
    overrides = overrides |> Enum.into(%{})

    params =
      %{
        "page" => Integer.to_string(overrides[:page] || socket.assigns.page),
        "page_size" => Integer.to_string(overrides[:page_size] || socket.assigns.page_size),
        "search" => overrides[:search] || socket.assigns.search,
        "status" => overrides[:status] || socket.assigns.status_filter,
        "sort_by" => overrides[:sort_by] || socket.assigns.sort_by,
        "sort_order" => overrides[:sort_order] || socket.assigns.sort_order
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
      |> Map.new()

    ~p"/admin/campaigns/#{socket.assigns.campaign.id}/winning-records?#{params}"
  end

  defp status_badge_variant("fulfilled"), do: "success"
  defp status_badge_variant("pending_process"), do: "warning"
  defp status_badge_variant("pending_submit"), do: "default"
  defp status_badge_variant("expired"), do: "error"
  defp status_badge_variant(_), do: "default"

  defp status_label("pending_submit"), do: "Pending Submit"
  defp status_label("pending_process"), do: "Pending Process"
  defp status_label("fulfilled"), do: "Fulfilled"
  defp status_label("expired"), do: "Expired"
  defp status_label(other), do: other

  defp format_datetime(nil), do: "-"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  defp escape_csv(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end

  defp escape_csv(value), do: escape_csv(to_string(value))
end
