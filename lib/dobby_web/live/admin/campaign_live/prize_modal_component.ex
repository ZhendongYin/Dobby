defmodule DobbyWeb.Admin.CampaignLive.PrizeModalComponent do
  @moduledoc """
  LiveComponent for managing the prize modal in campaign preview.
  """
  use DobbyWeb, :live_component

  alias Dobby.Campaigns
  alias Dobby.Campaigns.Prize
  alias Dobby.PrizeLibrary

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:prize_modal, fn -> default_prize_modal() end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="prize-modal-container">
      <%= if assigns.prize_modal.open? do %>
        {render_prize_modal(assigns)}
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("close_prize_modal", _params, socket) do
    send(self(), {__MODULE__, :close_modal})
    {:noreply, socket}
  end

  def handle_event("load_prize_template", %{"template_id" => ""}, socket) do
    modal = socket.assigns.prize_modal
    prize = modal.prize || %Prize{campaign_id: socket.assigns.campaign.id}
    changeset = Campaigns.change_prize(prize, %{})

    send(
      self(),
      {__MODULE__, :update_modal,
       %{
         selected_template_id: nil,
         form: to_form(changeset),
         template_locked_fields: []
       }}
    )

    {:noreply, socket}
  end

  def handle_event("load_prize_template", %{"template_id" => template_id}, socket) do
    modal = socket.assigns.prize_modal
    prize = modal.prize || %Prize{campaign_id: socket.assigns.campaign.id}

    template = PrizeLibrary.get_template!(template_id)

    form_attrs = %{
      "name" => template.name,
      "description" => template.description,
      "image_url" => template.image_url,
      "prize_type" => template.prize_type,
      "redemption_guide" => template.redemption_guide
    }

    changeset =
      prize
      |> Campaigns.change_prize(form_attrs)
      |> Ecto.Changeset.put_change(:source_template_id, template.id)
      |> Ecto.Changeset.put_change(:name, template.name)
      |> Ecto.Changeset.put_change(:description, template.description)
      |> Ecto.Changeset.put_change(:image_url, template.image_url)
      |> Ecto.Changeset.put_change(:prize_type, template.prize_type)
      |> Ecto.Changeset.put_change(:redemption_guide, template.redemption_guide)

    updated_prize = %{
      prize
      | name: template.name,
        description: template.description,
        image_url: template.image_url,
        prize_type: template.prize_type,
        redemption_guide: template.redemption_guide,
        source_template_id: template.id
    }

    locked_fields = ["name", "description", "image_url", "prize_type", "redemption_guide"]

    send(
      self(),
      {__MODULE__, :update_modal,
       %{
         form: to_form(changeset),
         prize: updated_prize,
         selected_template_id: template_id,
         template_locked_fields: locked_fields
       }}
    )

    {:noreply, socket}
  end

  def handle_event("validate_prize_modal", %{"prize" => prize_params}, socket) do
    modal = socket.assigns.prize_modal
    prize = modal.prize || %Prize{campaign_id: socket.assigns.campaign.id}

    changeset =
      prize
      |> Campaigns.change_prize(prize_params)
      |> Map.put(:action, :validate)

    updated_prize =
      if prize_params["prize_type"] do
        %{prize | prize_type: prize_params["prize_type"]}
      else
        prize
      end

    send(
      self(),
      {__MODULE__, :update_modal,
       %{
         form: to_form(changeset),
         prize: updated_prize
       }}
    )

    {:noreply, socket}
  end

  def handle_event("save_prize_modal", %{"prize" => prize_params}, socket) do
    modal = socket.assigns.prize_modal
    campaign = socket.assigns.campaign

    prize_params =
      prize_params
      |> normalize_quantity_field(:total_quantity)
      |> normalize_quantity_field(:remaining_quantity)

    admin_id = socket.assigns.current_admin.id

    send(
      self(),
      {__MODULE__, :save_prize,
       %{
         mode: modal.mode,
         prize: modal.prize,
         prize_params: prize_params,
         campaign_id: campaign.id,
         admin_id: admin_id
       }}
    )

    {:noreply, socket}
  end

  defp render_prize_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-base-content/60 backdrop-blur-sm"
      id="prize-modal-overlay"
    >
      <div class="bg-base-100 text-base-content rounded-3xl border border-base-300 shadow-2xl shadow-primary/20 w-full max-w-2xl max-h-[90vh] overflow-y-auto p-6 space-y-6">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-xs uppercase tracking-[0.3em] text-base-content/50">Prize Editor</p>
            <h2 class="text-2xl font-semibold mt-1">{@prize_modal.title}</h2>
          </div>
          <button
            type="button"
            phx-click="close_prize_modal"
            phx-target={@myself}
            class="text-base-content/50 hover:text-base-content/80 transition-colors"
          >
            <.icon name="hero-x-mark" class="h-6 w-6" />
          </button>
        </div>

        <div
          :if={@prize_modal.mode != "edit"}
          class="rounded-2xl border border-base-300 bg-base-200/60 p-4 space-y-2"
        >
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="text-sm font-semibold">快速套用模板</p>
              <p class="text-xs text-base-content/70">選擇模板會立即帶入欄位內容</p>
            </div>
          </div>
          <form phx-change="load_prize_template" phx-target={@myself} class="mt-2">
            <label class="sr-only" for="modal-template-select">選擇模板</label>
            <.select
              id="modal-template-select"
              name="template_id"
              value={@prize_modal.selected_template_id || ""}
              options={[{"", "建立全新獎品"}] ++ Enum.map(@prize_templates, fn t -> {t.id, t.name} end)}
              class="w-full rounded-xl"
            />
          </form>
        </div>

        <.form
          :if={@prize_modal.form}
          for={@prize_modal.form}
          id="preview-prize-form"
          class="space-y-4"
          phx-change="validate_prize_modal"
          phx-submit="save_prize_modal"
          phx-target={@myself}
        >
          <input
            type="hidden"
            name="prize[source_template_id]"
            value={
              (@prize_modal.form[:source_template_id] &&
                 @prize_modal.form[:source_template_id].value) || ""
            }
          />

          <div class="space-y-4">
            <.input
              field={@prize_modal.form[:name]}
              type="text"
              label="獎品名稱"
              required
              disabled={Enum.member?(@prize_modal.template_locked_fields, "name")}
            />
            <.input
              field={@prize_modal.form[:description]}
              type="textarea"
              label="獎品描述"
              rows="3"
              disabled={Enum.member?(@prize_modal.template_locked_fields, "description")}
            />
            <.input
              field={@prize_modal.form[:image_url]}
              type="text"
              label="圖片 URL"
              disabled={Enum.member?(@prize_modal.template_locked_fields, "image_url")}
            />
          </div>

          <div class="grid gap-4 md:grid-cols-2">
            <.input
              field={@prize_modal.form[:prize_type]}
              type="select"
              label="獎品類型"
              options={[{"實體", "physical"}, {"虛擬", "virtual"}, {"未中獎", "no_prize"}]}
              required
              disabled={Enum.member?(@prize_modal.template_locked_fields, "prize_type")}
            />
            <.input
              field={@prize_modal.form[:probability]}
              type="number"
              step="0.01"
              min="0"
              max="100"
              label="中獎機率 (%)"
              required
            />
          </div>

          <div
            :if={
              (@prize_modal.form[:prize_type] && @prize_modal.form[:prize_type].value == "virtual") ||
                (@prize_modal.prize && @prize_modal.prize.prize_type == "virtual")
            }
            class="space-y-2"
          >
            <div class="rounded-2xl border border-indigo-200 bg-indigo-50/50 p-4 space-y-2">
              <div class="flex items-center gap-2">
                <.icon name="hero-key" class="h-5 w-5 text-indigo-600" />
                <label class="text-sm font-semibold text-slate-900">兌換碼</label>
              </div>

              <.input
                field={@prize_modal.form[:prize_code]}
                type="text"
                label=""
                placeholder="輸入兌換碼，例如：PROMO-2024-ALL"
                required
              />
            </div>
          </div>

          <div class="grid gap-4 md:grid-cols-2">
            <div class="space-y-1">
              <.input
                field={@prize_modal.form[:total_quantity]}
                type="number"
                min="0"
                label="總數量"
                placeholder="留空表示不限量"
              />
              <p class="text-xs text-slate-500 px-1">
                留空表示不限量，不限制總發放數量
              </p>
            </div>
            <div class="space-y-1">
              <.input
                field={@prize_modal.form[:remaining_quantity]}
                type="number"
                min="0"
                label="剩餘數量"
                placeholder="留空表示不限量"
              />
              <p class="text-xs text-slate-500 px-1">
                留空表示不限量，不限制剩餘數量
              </p>
            </div>
          </div>

          <div class="grid gap-4 md:grid-cols-2">
            <.input
              field={@prize_modal.form[:daily_limit]}
              type="number"
              min="0"
              label="每日上限"
            />
            <.input field={@prize_modal.form[:display_order]} type="number" min="0" label="排序" />
          </div>

          <div class="space-y-1">
            <.input
              field={@prize_modal.form[:email_template_id]}
              type="select"
              label="郵件通知模板"
              prompt="跟隨活動預設"
              options={
                Enum.map(@email_template_options, fn template ->
                  {"#{template.name}", template.id}
                end)
              }
            />
            <p class="text-xs text-slate-500 px-1">
              留空表示沿用活動預設通知模板
            </p>
          </div>

          <.input
            :if={@campaign.enable_protection}
            field={@prize_modal.form[:is_protected]}
            type="checkbox"
            label="設為保護獎項"
          />

          <.input
            field={@prize_modal.form[:redemption_guide]}
            type="textarea"
            label="兌換說明"
            rows="3"
            disabled={Enum.member?(@prize_modal.template_locked_fields, "redemption_guide")}
          />


          <div class="flex justify-end gap-3 pt-4">
            <button
              type="button"
              phx-click="close_prize_modal"
              phx-target={@myself}
              class="px-4 py-2 rounded-xl border border-slate-300 text-slate-600 hover:bg-slate-50"
            >
              取消
            </button>
            <button
              type="submit"
              class="px-5 py-2 rounded-xl bg-indigo-600 text-white font-semibold hover:bg-indigo-500"
            >
              儲存
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp default_prize_modal do
    %{
      open?: false,
      mode: nil,
      title: nil,
      prize: nil,
      form: nil,
      selected_template_id: nil,
      template_locked_fields: []
    }
  end

  defp normalize_quantity_field(params, field) when is_atom(field) do
    field_str = to_string(field)
    value = Map.get(params, field_str) || Map.get(params, field)

    cond do
      value == "" || value == nil ->
        Map.put(params, field_str, nil)

      is_binary(value) ->
        case Integer.parse(value) do
          {num, _} ->
            Map.put(params, field_str, num)

          _ ->
            Map.put(params, field_str, nil)
        end

      is_integer(value) ->
        Map.put(params, field_str, value)

      true ->
        Map.put(params, field_str, nil)
    end
  end
end
