defmodule DobbyWeb.Admin.PrizeLive.Index do
  use DobbyWeb, :live_view

  alias Dobby.Campaigns
  alias Dobby.Campaigns.Prize
  alias Dobby.PrizeLibrary
  alias DobbyWeb.LiveViewHelpers

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, %{"campaign_id" => campaign_id} = params) do
    campaign = Campaigns.get_campaign!(campaign_id)
    page = LiveViewHelpers.parse_integer(params["page"], socket.assigns[:page] || 1)

    page_size =
      LiveViewHelpers.parse_integer(params["page_size"], socket.assigns[:page_size] || 20)

    result = Campaigns.list_prizes(campaign_id, %{page: page, page_size: page_size})

    socket
    |> assign(:page_title, "Prizes - #{campaign.name}")
    |> assign(:campaign, campaign)
    |> assign(:prizes, result.items)
    |> assign(:prizes_total, result.total)
    |> assign(:prizes_page, result.page)
    |> assign(:prizes_page_size, result.page_size)
    |> assign(:prize, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, %{"campaign_id" => campaign_id}) do
    campaign = Campaigns.get_campaign!(campaign_id)
    changeset = Campaigns.change_prize(%Prize{campaign_id: campaign_id})
    form = to_form(changeset)

    socket
    |> assign(:page_title, "New Prize")
    |> assign(:campaign, campaign)
    |> assign(:prizes, [])
    |> assign(:prize, %Prize{campaign_id: campaign_id})
    |> assign(:form, form)
  end

  defp apply_action(socket, :edit, %{"campaign_id" => campaign_id, "id" => id}) do
    campaign = Campaigns.get_campaign!(campaign_id)
    prize = Campaigns.get_prize!(id)
    changeset = Campaigns.change_prize(prize)
    form = to_form(changeset)
    result = Campaigns.list_prizes(campaign_id, %{page: 1, page_size: 20})

    socket
    |> assign(:page_title, "Edit Prize")
    |> assign(:campaign, campaign)
    |> assign(:prizes, result.items)
    |> assign(:prize, prize)
    |> assign(:form, form)
  end

  defp apply_action(socket, :import, %{"campaign_id" => campaign_id}) do
    campaign = Campaigns.get_campaign!(campaign_id)
    result = Campaigns.list_prizes(campaign_id, %{page: 1, page_size: 20})

    socket
    |> assign(:page_title, "Import Prize")
    |> assign(:campaign, campaign)
    |> assign(:templates, PrizeLibrary.list_templates(%{}).items)
    |> assign(:prizes, result.items)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    prize = Campaigns.get_prize!(id)
    {:ok, _} = Campaigns.delete_prize(prize)

    result =
      Campaigns.list_prizes(socket.assigns.campaign.id, %{
        page: socket.assigns[:prizes_page] || 1,
        page_size: socket.assigns[:prizes_page_size] || 20
      })

    {:noreply,
     socket
     |> put_flash(:info, "Prize deleted successfully")
     |> assign(:prizes, result.items)
     |> assign(:prizes_total, result.total)
     |> assign(:prizes_page, result.page)
     |> assign(:prizes_page_size, result.page_size)}
  end

  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    page_size = LiveViewHelpers.parse_integer(page_size, 20)

    {:noreply,
     socket
     |> assign(:prizes_page_size, page_size)
     |> assign(:prizes_page, 1)
     |> push_patch(to: build_pagination_path(socket, 1, page_size))}
  end

  def handle_event("go_to_page", %{"page" => page}, socket) do
    page = LiveViewHelpers.parse_integer(page, 1)

    {:noreply,
     socket
     |> assign(:prizes_page, page)
     |> push_patch(to: build_pagination_path(socket, page, socket.assigns.prizes_page_size))}
  end

  def handle_event("validate", %{"prize" => prize_params}, socket) do
    changeset =
      socket.assigns.prize
      |> Campaigns.change_prize(prize_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"prize" => prize_params}, socket) do
    prize_params = normalize_prize_params(prize_params)

    case socket.assigns.live_action do
      :new ->
        case Campaigns.create_prize(prize_params) do
          {:ok, _prize} ->
            {:noreply,
             socket
             |> put_flash(:info, "Prize created successfully")
             |> push_navigate(to: ~p"/admin/campaigns/#{socket.assigns.campaign.id}/prizes")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end

      :edit ->
        case Campaigns.update_prize(socket.assigns.prize, prize_params) do
          {:ok, _prize} ->
            {:noreply,
             socket
             |> put_flash(:info, "Prize updated successfully")
             |> push_navigate(to: ~p"/admin/campaigns/#{socket.assigns.campaign.id}/prizes")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, form: to_form(changeset))}
        end
    end
  end

  defp normalize_prize_params(params) do
    params
    |> normalize_decimal_field(:probability)
    |> normalize_integer_field(:total_quantity)
    |> normalize_integer_field(:remaining_quantity)
    |> normalize_integer_field(:daily_limit)
    |> normalize_integer_field(:weight)
    |> normalize_integer_field(:display_order)
    |> normalize_checkbox_field(:is_protected)
  end

  defp normalize_decimal_field(params, field) when is_atom(field) do
    field_str = Atom.to_string(field)

    if value = params[field_str] do
      case Decimal.parse(to_string(value)) do
        {decimal, _} ->
          Map.put(params, field_str, decimal)

        :error ->
          params
      end
    else
      params
    end
  end

  defp normalize_integer_field(params, field) when is_atom(field) do
    field_str = Atom.to_string(field)
    value = Map.get(params, field_str)

    cond do
      value == nil or value == "" ->
        Map.put(params, field_str, nil)

      is_binary(value) ->
        case Integer.parse(value) do
          {int, _} -> Map.put(params, field_str, int)
          :error -> Map.put(params, field_str, nil)
        end

      is_integer(value) ->
        Map.put(params, field_str, value)

      true ->
        Map.put(params, field_str, nil)
    end
  end

  defp normalize_checkbox_field(params, field) when is_atom(field) do
    field_str = Atom.to_string(field)

    value =
      case params[field_str] do
        "true" -> true
        "false" -> false
        true -> true
        false -> false
        "1" -> true
        "0" -> false
        _ -> false
      end

    Map.put(params, field_str, value)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :admin, current_nav: :campaigns}}>
      <.page_container>
        <%= if @live_action in [:new, :edit] do %>
          <.live_component
            module={DobbyWeb.Admin.PrizeLive.FormComponent}
            id={@prize.id || :new}
            title={@page_title}
            action={@live_action}
            prize={@prize}
            campaign={@campaign}
            form={@form}
            return_to={~p"/admin/campaigns/#{@campaign.id}/prizes"}
          />
        <% else %>
          <%= if @live_action == :import do %>
            <.live_component
              module={DobbyWeb.Admin.PrizeLive.ImportComponent}
              id={:import}
              title={@page_title}
              campaign={@campaign}
              templates={@templates}
              return_to={~p"/admin/campaigns/#{@campaign.id}/prizes"}
            />
          <% else %>
            <div class="flex flex-wrap items-center justify-between gap-4 mb-8">
              <.page_header
                title="Prizes"
                subtitle={"Manage prizes for: #{@campaign.name}"}
              />
              <div class="flex gap-3">
                <.secondary_button navigate={~p"/admin/campaigns/#{@campaign.id}/prizes/import"}>
                  Import from Library
                </.secondary_button>
                <.primary_button navigate={~p"/admin/campaigns/#{@campaign.id}/prizes/new"}>
                  <.icon name="hero-plus-small" class="w-4 h-4" /> Add Prize
                </.primary_button>
              </div>
            </div>

            <.card>
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-base-300 bg-base-100 text-base-content">
                  <thead class="bg-base-200/80 text-xs font-semibold uppercase tracking-[0.2em] text-base-content/70">
                    <tr>
                      <th
                        scope="col"
                        class="py-3.5 pl-4 pr-3 text-left"
                      >
                        Name
                      </th>
                      <th
                        scope="col"
                        class="px-3 py-3.5 text-left"
                      >
                        Type
                      </th>
                      <th
                        scope="col"
                        class="px-3 py-3.5 text-left"
                      >
                        Probability
                      </th>
                      <th
                        scope="col"
                        class="px-3 py-3.5 text-left"
                      >
                        Quantity
                      </th>
                      <th
                        scope="col"
                        class="px-3 py-3.5 text-left"
                      >
                        Order
                      </th>
                      <th scope="col" class="relative py-3.5 pl-3 pr-4 sm:pr-6">
                        <span class="sr-only">Actions</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-base-200 bg-base-100 text-sm">
                    <tr
                      :for={prize <- @prizes}
                      id={"prize-#{prize.id}"}
                      class="hover:bg-base-200/50 transition-colors"
                    >
                      <td class="py-4 pl-4 pr-3 font-medium text-base-content sm:pl-6 max-w-xs">
                        <div class="truncate" title={prize.name}>
                          {prize.name}
                        </div>
                      </td>
                      <td class="px-3 py-4 text-base-content/70 whitespace-nowrap">
                        {String.capitalize(prize.prize_type || "no_prize")}
                      </td>
                      <td class="px-3 py-4 text-base-content/70 whitespace-nowrap">
                        <%= if prize.probability do %>
                          {:erlang.float_to_binary(Decimal.to_float(prize.probability), decimals: 2)}%
                        <% else %>
                          -
                        <% end %>
                      </td>
                      <td class="px-3 py-4 text-base-content/70 whitespace-nowrap">
                        <%= if is_nil(prize.total_quantity) do %>
                          不限量
                        <% else %>
                          {prize.remaining_quantity || 0}/{prize.total_quantity}
                        <% end %>
                      </td>
                      <td class="px-3 py-4 text-base-content/70 whitespace-nowrap">
                        {prize.display_order}
                      </td>
                      <td class="relative py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-6 whitespace-nowrap">
                        <div class="flex gap-2 justify-end">
                          <.link
                            navigate={~p"/admin/campaigns/#{@campaign.id}/prizes/#{prize.id}/edit"}
                            class="text-primary hover:text-primary/80"
                          >
                            Edit
                          </.link>
                          <button
                            phx-click="delete"
                            phx-value-id={prize.id}
                            data-confirm="Are you sure?"
                            class="text-error hover:text-error/80"
                          >
                            Delete
                          </button>
                        </div>
                      </td>
                    </tr>
                    <tr :if={Enum.empty?(@prizes)}>
                      <td colspan="6" class="px-4 py-12 text-center text-slate-500 text-sm">
                        No prizes found. Add your first prize to get started.
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <.pagination
                :if={!Enum.empty?(@prizes)}
                page={@prizes_page}
                page_size={@prizes_page_size}
                total={@prizes_total}
                path={~p"/admin/campaigns/#{@campaign.id}/prizes"}
                params={%{}}
              />
            </.card>
          <% end %>
        <% end %>
      </.page_container>
    </Layouts.app>
    """
  end

  defp build_pagination_path(socket, page, page_size) do
    params = %{
      "page" => Integer.to_string(page),
      "page_size" => Integer.to_string(page_size)
    }

    ~p"/admin/campaigns/#{socket.assigns.campaign.id}/prizes?#{params}"
  end
end
