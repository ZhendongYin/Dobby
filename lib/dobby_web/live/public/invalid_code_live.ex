defmodule DobbyWeb.Public.InvalidCodeLive do
  use DobbyWeb, :live_view

  alias Dobby.Campaigns
  alias Ecto.NoResultsError

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"campaign_id" => campaign_id}, _uri, socket) do
    case fetch_campaign(campaign_id) do
      {:ok, campaign} ->
        {:noreply, assign(socket, :campaign, campaign)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "找不到此活動。")
         |> push_navigate(to: ~p"/")}
    end
  end

  defp fetch_campaign(id) do
    try do
      {:ok, Campaigns.get_campaign!(id)}
    rescue
      NoResultsError ->
        {:error, :not_found}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :public}}>
      <div class="min-h-[70vh] flex items-center justify-center px-4 py-16 bg-base-200">
        <div class="max-w-md w-full rounded-3xl bg-base-100 border border-base-300 shadow-xl p-8 space-y-6 text-center">
          <div class="inline-flex h-16 w-16 items-center justify-center rounded-full bg-rose-100 text-rose-600 mx-auto">
            <.icon name="hero-exclamation-triangle" class="h-8 w-8" />
          </div>
          <div class="space-y-2">
            <h1 class="text-xl font-bold text-base-content">無法參與抽獎</h1>
            <p class="text-sm text-base-content/70 leading-relaxed">
              此抽獎碼無效、不在本活動名單內，或不屬於本活動。請確認連結是否正確；頁首亦會顯示詳細原因。
            </p>
          </div>
          <p :if={@campaign} class="text-xs text-base-content/50">
            活動：{@campaign.name}
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
