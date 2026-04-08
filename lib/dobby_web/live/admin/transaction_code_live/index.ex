defmodule DobbyWeb.Admin.TransactionCodeLive.Index do
  use DobbyWeb, :live_view

  alias Dobby.Campaigns
  alias Dobby.Lottery
  alias DobbyWeb.LiveViewHelpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:qr_modal_open, false)
     |> assign(:qr_target_code, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, params)}
  end

  defp apply_action(socket, params) do
    %{"campaign_id" => campaign_id} = params
    admin_id = socket.assigns.current_admin.id
    campaign = Campaigns.get_campaign_for_admin!(campaign_id, admin_id)

    page = LiveViewHelpers.parse_integer(params["page"], socket.assigns[:page] || 1)

    page_size =
      LiveViewHelpers.parse_integer(params["page_size"], socket.assigns[:page_size] || 50)

    search = params["search"] || socket.assigns[:search] || ""

    result =
      Lottery.list_transaction_numbers(campaign.id, %{
        page: page,
        page_size: page_size,
        search: search
      })

    socket
    |> assign(:page_title, "抽獎碼 · #{campaign.name}")
    |> assign(:campaign, campaign)
    |> assign(:page, page)
    |> assign(:page_size, page_size)
    |> assign(:search, search)
    |> assign(:codes, result.items)
    |> assign(:codes_total, result.total)
    |> assign(:codes_total_pages, result.total_pages)
  end

  @impl true
  def handle_event("search_change", %{"search" => search}, socket) do
    search = search || ""

    {:noreply, push_patch(socket, to: current_path(socket, search: search, page: 1))}
  end

  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    page_size = LiveViewHelpers.parse_integer(page_size, 50)

    {:noreply, push_patch(socket, to: current_path(socket, page: 1, page_size: page_size))}
  end

  def handle_event("go_to_page", %{"page" => page}, socket) do
    page = LiveViewHelpers.parse_integer(page, 1)

    {:noreply, push_patch(socket, to: current_path(socket, page: page))}
  end

  def handle_event("import_codes", params, socket) do
    text = Map.get(params, "text") || ""

    {:ok, stats} =
      Lottery.import_transaction_codes(socket.assigns.campaign.id, text)

    msg =
      "匯入完成：新增 #{stats.inserted} 筆" <>
        if(stats.skipped_due_to_duplicate > 0,
          do: "，略過 #{stats.skipped_due_to_duplicate} 筆（重複或已存在）。",
          else: "。"
        )

    {:noreply,
     socket
     |> put_flash(:info, msg)
     |> push_patch(to: current_path(socket, page: 1))}
  end

  def handle_event("add_one", params, socket) do
    code = Map.get(params, "code") || ""

    case Lottery.add_transaction_code(socket.assigns.campaign.id, code) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "已新增抽獎碼。")
         |> push_patch(to: current_path(socket, page: 1))}

      {:error, :blank} ->
        {:noreply, put_flash(socket, :error, "抽獎碼不能為空。")}

      {:error, %Ecto.Changeset{} = cs} ->
        msg =
          cs.errors
          |> Enum.map(fn {f, {m, _}} -> "#{f} #{m}" end)
          |> Enum.join("；")

        {:noreply, put_flash(socket, :error, msg || "新增失敗。")}
    end
  end

  def handle_event("show_qr", %{"code" => code}, socket) do
    {:noreply,
     socket
     |> assign(:qr_modal_open, true)
     |> assign(:qr_target_code, code)}
  end

  def handle_event("close_qr", _params, socket) do
    {:noreply,
     socket
     |> assign(:qr_modal_open, false)
     |> assign(:qr_target_code, nil)}
  end

  defp current_path(socket, overrides) do
    c = socket.assigns.campaign

    page = Keyword.get(overrides, :page, socket.assigns.page)
    page_size = Keyword.get(overrides, :page_size, socket.assigns.page_size)
    search = Keyword.get(overrides, :search, socket.assigns.search) || ""

    params = %{
      "page" => to_string(page),
      "page_size" => to_string(page_size),
      "search" => search
    }

    ~p"/admin/campaigns/#{c.id}/transaction-codes?#{params}"
  end

  defp public_scratch_url(campaign_id, code) do
    scheme = System.get_env("PHX_PUBLIC_SCHEME") || "http"
    host = System.get_env("PHX_HOST") || "localhost"
    port = System.get_env("PHX_PUBLIC_PORT")

    base =
      case String.trim(port || "") do
        "" ->
          "#{scheme}://#{host}"

        "80" when scheme == "http" ->
          "#{scheme}://#{host}"

        "443" when scheme == "https" ->
          "#{scheme}://#{host}"

        trimmed ->
          "#{scheme}://#{host}:#{trimmed}"
      end

    "#{base}/campaigns/#{campaign_id}/scratch/#{code}"
  end

  defp qr_image_src(url) do
    # Render QR through a stable GET endpoint so no extra JS dependency is required.
    "https://quickchart.io/qr?size=260&text=#{URI.encode_www_form(url)}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :admin, current_nav: :campaigns}}>
      <.page_container>
        <div class="max-w-5xl mx-auto space-y-8">
          <div class="flex flex-wrap items-center justify-between gap-4">
            <div>
              <p class="text-xs uppercase tracking-widest text-base-content/50">Campaign</p>
              <h1 class="text-2xl font-bold text-base-content mt-1">抽獎碼管理</h1>
              <p class="text-sm text-base-content/60 mt-1">{@campaign.name}</p>
            </div>
            <div class="flex flex-wrap gap-2">
              <.link
                navigate={~p"/admin/campaigns/#{@campaign.id}/preview"}
                class="btn btn-ghost btn-sm"
              >
                返回活動
              </.link>
              <.link navigate={~p"/admin/campaigns/#{@campaign.id}/edit"} class="btn btn-outline btn-sm">
                編輯設定
              </.link>
            </div>
          </div>

          <div class="rounded-2xl border border-base-300 bg-base-100 p-6 space-y-4">
            <div class="flex items-start gap-3">
              <.icon name="hero-information-circle" class="h-5 w-5 text-primary flex-shrink-0 mt-0.5" />
              <div class="text-sm text-base-content/70 space-y-1">
                <p :if={@campaign.require_preimported_codes}>
                  此活動已設定為 <span class="font-semibold text-base-content">僅允許已新增的抽獎碼</span>
                  參與抽獎。未在列表中的抽獎碼將無法開獎。
                </p>
                <p :if={!@campaign.require_preimported_codes}>
                  此活動<strong class="text-base-content">未</strong>限制抽獎碼須預先匯入；未列於此處的抽獎碼仍可能在通過外部驗證後自動建立。
                </p>
              </div>
            </div>
          </div>

          <div class="grid gap-6 lg:grid-cols-2">
            <div class="rounded-2xl border border-base-300 bg-base-100 p-6 space-y-4">
              <h2 class="font-semibold text-base-content">手動新增</h2>
              <form phx-submit="add_one" class="space-y-3">
                <input
                  type="text"
                  name="code"
                  placeholder="輸入一組抽獎碼"
                  class="input input-bordered w-full"
                  autocomplete="off"
                />
                <button type="submit" class="btn btn-primary btn-sm">新增</button>
              </form>
            </div>

            <div class="rounded-2xl border border-base-300 bg-base-100 p-6 space-y-4">
              <h2 class="font-semibold text-base-content">批量匯入</h2>
              <p class="text-xs text-base-content/60">每行一組，或以逗號分隔。重複（含他活動已使用）將自動略過。</p>
              <form phx-submit="import_codes" class="space-y-3">
                <textarea
                  name="text"
                  rows="6"
                  placeholder="CODE001&#10;CODE002"
                  class="textarea textarea-bordered w-full font-mono text-sm"
                ></textarea>
                <button type="submit" class="btn btn-primary btn-sm">匯入</button>
              </form>
            </div>
          </div>

          <div class="rounded-2xl border border-base-300 bg-base-100 p-6 space-y-4">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="font-semibold text-base-content">抽獎碼列表（共 {@codes_total} 筆）</h2>
              <form phx-change="search_change" id="tx-code-search" class="w-full sm:w-auto">
                <input
                  type="search"
                  name="search"
                  value={@search}
                  phx-debounce="300"
                  placeholder="搜尋抽獎碼…"
                  class="input input-bordered input-sm w-full sm:w-48"
                />
              </form>
            </div>

            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>抽獎碼</th>
                    <th>狀態</th>
                    <th>建立時間</th>
                    <th class="text-right">操作</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @codes} id={"tx-#{row.id}"}>
                    <td class="font-mono text-sm">{row.transaction_number}</td>
                    <td>
                      <%= if row.is_used do %>
                        <span class="badge badge-warning badge-sm">已使用</span>
                      <% else %>
                        <span class="badge badge-success badge-sm">未使用</span>
                      <% end %>
                    </td>
                    <td class="text-xs text-base-content/60">
                      {Calendar.strftime(row.inserted_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="text-right">
                      <button
                        type="button"
                        phx-click="show_qr"
                        phx-value-code={row.transaction_number}
                        class="btn btn-xs btn-outline"
                      >
                        QR Code
                      </button>
                    </td>
                  </tr>
                  <tr :if={Enum.empty?(@codes)}>
                    <td colspan="4" class="text-center text-base-content/50 py-8">
                      尚無抽獎碼，請先新增或匯入。
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <.pagination
              :if={@codes_total > 0}
              page={@page}
              page_size={@page_size}
              total={@codes_total}
              path={~p"/admin/campaigns/#{@campaign.id}/transaction-codes"}
              params={%{"search" => @search}}
            />
          </div>
        </div>

        <div :if={@qr_modal_open && @qr_target_code} class="fixed inset-0 z-50">
          <div
            class="absolute inset-0 bg-black/60 backdrop-blur-sm"
            phx-click="close_qr"
          >
          </div>

          <div class="absolute inset-0 flex items-center justify-center p-4">
            <div class="w-full max-w-md rounded-2xl border border-base-300 bg-base-100 p-6 space-y-4 shadow-2xl">
              <div class="flex items-center justify-between">
                <h3 class="text-lg font-semibold text-base-content">抽獎碼 QR Code</h3>
                <button type="button" phx-click="close_qr" class="btn btn-ghost btn-xs">關閉</button>
              </div>

              <% scratch_url = public_scratch_url(@campaign.id, @qr_target_code) %>
              <p class="text-xs text-base-content/60 break-all">{scratch_url}</p>

              <div class="flex justify-center">
                <img
                  src={qr_image_src(scratch_url)}
                  alt={"QR for #{@qr_target_code}"}
                  class="rounded-xl border border-base-300 bg-white p-2"
                />
              </div>
            </div>
          </div>
        </div>
      </.page_container>
    </Layouts.app>
    """
  end
end
