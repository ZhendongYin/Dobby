defmodule DobbyWeb.Admin.PrizeLive.ImportComponent do
  use DobbyWeb, :live_component

  alias Dobby.Campaigns
  alias Dobby.PrizeLibrary
  alias Dobby.PrizeLibrary.PrizeTemplate

  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>從獎品庫挑選模板，並為此活動設定專屬數量與概率。</:subtitle>
      </.header>

      <div class="grid gap-6 lg:grid-cols-[2fr,3fr]">
        <div class="rounded-2xl border border-slate-200 bg-white p-4 space-y-3">
          <p class="text-xs uppercase tracking-[0.4em] text-slate-400">模板列表</p>
          <div class="space-y-2 max-h-[420px] overflow-y-auto pr-2">
            <button
              :for={template <- @templates}
              type="button"
              phx-click="select-template"
              phx-target={@myself}
              phx-value-id={template.id}
              class={[
                "w-full text-left rounded-2xl border px-3 py-2 transition",
                not is_nil(@selected_template) &&
                  @selected_template.id == template.id &&
                  "border-indigo-300 bg-indigo-50",
                (is_nil(@selected_template) || @selected_template.id != template.id) &&
                  "border-slate-200 hover:bg-slate-50"
              ]}
            >
              <p class="font-semibold text-slate-900">{template.name}</p>
              <p class="text-xs text-slate-500">{type_label(template.prize_type)}</p>
            </button>
          </div>
        </div>

        <div class="rounded-2xl border border-slate-200 bg-white p-6">
          <%= if @selected_template do %>
            <div class="space-y-4">
              <div>
                <p class="text-xs uppercase tracking-[0.4em] text-slate-400">已選模板</p>
                <h3 class="mt-2 text-xl font-semibold text-slate-900">{@selected_template.name}</h3>
                <p class="text-sm text-slate-500 whitespace-pre-wrap">
                  {@selected_template.description}
                </p>
              </div>

              <.form for={@form} phx-target={@myself} phx-submit="save" class="space-y-4">
                <div class="grid gap-4 md:grid-cols-2">
                  <.input
                    field={@form[:total_quantity]}
                    type="number"
                    label="總數量"
                    min="0"
                    required
                  />
                  <.input
                    field={@form[:remaining_quantity]}
                    type="number"
                    label="剩餘數量"
                    min="0"
                    required
                  />
                </div>

                <.input
                  field={@form[:probability_mode]}
                  type="select"
                  label="概率模式"
                  options={[{"百分比", "percentage"}, {"權重", "quantity_based"}]}
                />

                <div class="grid gap-4 md:grid-cols-2">
                  <.input field={@form[:probability]} type="number" step="0.01" label="概率 (%)" />
                  <.input field={@form[:weight]} type="number" label="權重" min="0" />
                </div>

                <.input
                  field={@form[:display_order]}
                  type="number"
                  min="0"
                  label="顯示排序"
                />

                <.input field={@form[:is_protected]} type="checkbox" label="適用保護機制" />

                <.button
                  class="bg-indigo-600 text-white hover:bg-indigo-500"
                  phx-disable-with="匯入中..."
                >
                  匯入至活動
                </.button>
                <.link navigate={@return_to} class="ml-4 text-sm text-slate-500">
                  取消
                </.link>
              </.form>
            </div>
          <% else %>
            <div class="text-center text-slate-500 py-24">
              請先選擇左側模板
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:templates, fn -> PrizeLibrary.list_templates() end)
     |> assign_new(:selected_template, fn -> nil end)
     |> assign_form()}
  end

  def handle_event("select-template", %{"id" => id}, socket) do
    template =
      socket.assigns.templates
      |> Enum.find(&(&1.id == id))

    {:noreply,
     socket
     |> assign(:selected_template, template)
     |> assign(:form, default_form())}
  end

  def handle_event("save", %{"import" => params}, socket) do
    with %PrizeTemplate{} = template <- socket.assigns.selected_template,
         {:ok, _prize} <-
           Campaigns.create_prize_from_template(template.id, socket.assigns.campaign.id, params) do
      {:noreply,
       socket
       |> put_flash(:info, "已匯入獎品")
       |> push_navigate(to: socket.assigns.return_to)}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "請先選擇模板")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp assign_form(socket) do
    assign(socket, :form, default_form())
  end

  defp default_form do
    data = %{
      total_quantity: 0,
      remaining_quantity: 0,
      probability_mode: "percentage",
      probability: nil,
      weight: nil,
      display_order: 0,
      is_protected: false
    }

    to_form(data, as: :import)
  end

  defp type_label("physical"), do: "實體"
  defp type_label("virtual"), do: "虛擬"
  defp type_label("no_prize"), do: "未中獎"
  defp type_label(_), do: "其他"
end
