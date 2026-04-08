defmodule DobbyWeb.Admin.CampaignShellComponents do
  @moduledoc false
  use DobbyWeb, :html

  attr :campaign, :map, required: true
  attr :active_tab, :string, required: true
  attr :prizes_count, :integer, default: 0
  attr :winners_count, :integer, default: 0
  attr :status, :string, default: nil
  attr :status_label, :string, default: nil
  attr :status_class, :string, default: nil
  slot :inner_block, required: true

  def campaign_shell(assigns) do
    status_label = assigns.status_label || shell_status_label(assigns.status)
    status_class = assigns.status_class || shell_status_color(assigns.status)

    assigns =
      assigns
      |> assign(:resolved_status_label, status_label)
      |> assign(:resolved_status_class, status_class)

    ~H"""
    <div class="w-full space-y-6">
      <div class="flex flex-wrap items-center justify-end gap-2 mb-8">
        <.primary_button navigate={~p"/admin/campaigns/#{@campaign.id}/edit"}>
          <.icon name="hero-pencil" class="h-4 w-4" /> 編輯活動
        </.primary_button>
      </div>

      <div class="bg-base-100 text-base-content rounded-2xl shadow-lg shadow-primary/10 border border-base-300 overflow-hidden transition-colors">
        <div class="relative">
          <div :if={@campaign.background_image_url} class="h-64 w-full overflow-hidden">
            <img
              src={@campaign.background_image_url}
              alt="Campaign Background"
              class="w-full h-full object-cover"
            />
          </div>
          <div
            :if={!@campaign.background_image_url}
            class="h-64 w-full bg-gradient-to-br from-indigo-500 via-purple-500 to-pink-500 flex items-center justify-center"
          >
            <div class="text-center text-white">
              <.icon name="hero-ticket" class="h-16 w-16 mx-auto mb-4 opacity-50" />
              <p class="text-lg font-semibold opacity-75">無背景圖片</p>
            </div>
          </div>
          <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent"></div>
          <div class="absolute inset-0 flex flex-col justify-between p-8 text-white">
            <div class="pt-4 space-y-3">
              <div class="flex items-center gap-3 flex-wrap">
                <span
                  :if={@resolved_status_label}
                  class={[
                    "inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold",
                    @resolved_status_class || "bg-white/25 text-white"
                  ]}
                >
                  {@resolved_status_label}
                </span>
                <div class="flex items-center gap-2 rounded-full bg-white/20 backdrop-blur-sm px-3 py-1.5 text-[11px] font-mono text-white/90">
                  <span class="truncate max-w-[200px]">活动ID: {@campaign.id}</span>
                  <button
                    type="button"
                    id={"campaign-preview-id-copy-#{@campaign.id}"}
                    phx-hook="CopyToClipboard"
                    phx-click-bubble="false"
                    data-copy-text={@campaign.id}
                    data-copy-success-label="已复制"
                    aria-label="複製活動 ID"
                    class="inline-flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full border border-white/30 text-white hover:bg-white/20 transition-colors"
                  >
                    <.icon name="hero-document-duplicate" class="h-3.5 w-3.5" />
                  </button>
                </div>
              </div>
              <h1 class="text-5xl font-black leading-tight">{@campaign.name || "未命名活動"}</h1>
            </div>
            <div class="pb-4">
              <p :if={@campaign.description} class="text-xl font-medium text-white/95 max-w-2xl">
                {@campaign.description}
              </p>
              <p :if={!@campaign.description} class="text-lg text-white/70 italic">
                尚未提供描述
              </p>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 transition-colors">
        <div class="border-b border-base-200">
          <nav class="flex overflow-x-auto" aria-label="Tabs">
            <a
              href={~p"/admin/campaigns/#{@campaign.id}/preview?#{[tab: "overview"]}"}
              class={tab_classes(@active_tab == "overview")}
            >
              <.icon name="hero-information-circle" class="h-4 w-4 inline mr-2" /> 概覽
            </a>
            <a
              href={~p"/admin/campaigns/#{@campaign.id}/preview?#{[tab: "prizes"]}"}
              class={tab_classes(@active_tab == "prizes")}
            >
              <.icon name="hero-gift" class="h-4 w-4 inline mr-2" /> 獎品管理
              <span class="ml-2 px-2 py-0.5 text-xs bg-slate-100 text-slate-600 rounded-full">
                {@prizes_count}
              </span>
            </a>
            <a
              href={~p"/admin/campaigns/#{@campaign.id}/transaction-codes"}
              class={tab_classes(@active_tab == "codes")}
            >
              <.icon name="hero-ticket" class="h-4 w-4 inline mr-2" /> 抽獎碼
            </a>
            <a
              href={~p"/admin/campaigns/#{@campaign.id}/preview?#{[tab: "winners"]}"}
              class={tab_classes(@active_tab == "winners")}
            >
              <.icon name="hero-trophy" class="h-4 w-4 inline mr-2" /> 獲獎記錄
              <span class="ml-2 px-2 py-0.5 text-xs bg-slate-100 text-slate-600 rounded-full">
                {@winners_count}
              </span>
            </a>
            <a
              href={~p"/admin/campaigns/#{@campaign.id}/preview?#{[tab: "activity"]}"}
              class={tab_classes(@active_tab == "activity")}
            >
              <.icon name="hero-clock" class="h-4 w-4 inline mr-2" /> 活動日誌
            </a>
          </nav>
        </div>

        <div class="p-6">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  defp tab_classes(active?) do
    [
      "px-6 py-4 text-sm font-semibold border-b-2 transition-colors whitespace-nowrap",
      if(active?,
        do: "border-indigo-500 text-indigo-600",
        else: "border-transparent text-slate-500 hover:text-slate-700 hover:border-slate-300"
      )
    ]
  end

  defp shell_status_color("active"), do: "bg-green-100 text-green-800"
  defp shell_status_color("draft"), do: "bg-gray-100 text-gray-800"
  defp shell_status_color("ended"), do: "bg-blue-100 text-blue-800"
  defp shell_status_color("disabled"), do: "bg-red-100 text-red-800"
  defp shell_status_color(_), do: "bg-gray-100 text-gray-800"

  defp shell_status_label("active"), do: "Active"
  defp shell_status_label("draft"), do: "Draft"
  defp shell_status_label("ended"), do: "Ended"
  defp shell_status_label("disabled"), do: "Disabled"
  defp shell_status_label(status) when is_binary(status), do: String.capitalize(status)
  defp shell_status_label(_), do: nil
end
