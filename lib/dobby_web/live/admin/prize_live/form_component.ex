defmodule DobbyWeb.Admin.PrizeLive.FormComponent do
  use DobbyWeb, :live_component

  alias Dobby.Campaigns
  import Phoenix.Component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
        <:subtitle>Use this form to manage prize records in your database.</:subtitle>
      </.header>

      <.form
        for={@form}
        id="prize-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
        class="space-y-6"
      >
        <.input field={@form[:name]} type="text" label="Name" required />
        <.input field={@form[:description]} type="textarea" label="Description" rows="4" />
        <.input
          field={@form[:image_url]}
          type="text"
          label="Image URL"
          placeholder="https://example.com/image.jpg"
        />

        <.input
          field={@form[:prize_type]}
          type="select"
          label="Prize Type"
          options={prize_type_options()}
          required
        />

        <.input
          field={@form[:probability_mode]}
          type="select"
          label="Probability Mode"
          options={probability_mode_options()}
          required
        />

        <div :if={@form[:probability_mode].value == "percentage"} class="space-y-4">
          <.input
            field={@form[:probability]}
            type="number"
            label="Probability (%)"
            step="0.01"
            min="0"
            max="100"
            placeholder="0.00"
          />
        </div>

        <div :if={@form[:probability_mode].value == "quantity_based"} class="space-y-4">
          <.input
            field={@form[:weight]}
            type="number"
            label="Weight"
            min="1"
            placeholder="1"
          />
        </div>

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:total_quantity]}
            type="number"
            label="Total Quantity"
            min="0"
            placeholder="0"
          />
          <.input
            field={@form[:remaining_quantity]}
            type="number"
            label="Remaining Quantity"
            min="0"
            placeholder="0"
          />
        </div>

        <.input
          field={@form[:daily_limit]}
          type="number"
          label="Daily Limit"
          min="0"
          placeholder="Unlimited"
        />

        <.input
          field={@form[:display_order]}
          type="number"
          label="Display Order"
          min="0"
          placeholder="0"
        />

        <.input
          field={@form[:is_protected]}
          type="checkbox"
          label="Protected Prize"
        />

        <.input
          field={@form[:redemption_guide]}
          type="textarea"
          label="Redemption Guide"
          rows="3"
        />

        <div class="flex gap-4 mt-6">
          <.button
            phx-disable-with="Saving..."
            class="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700"
          >
            Save Prize
          </.button>
          <.link
            navigate={@return_to}
            class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{prize: prize} = assigns, socket) do
    changeset = Campaigns.change_prize(prize)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"prize" => prize_params}, socket) do
    changeset =
      socket.assigns.prize
      |> Campaigns.change_prize(prize_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"prize" => prize_params}, socket) do
    save_prize(socket, socket.assigns.action, prize_params)
  end

  defp save_prize(socket, :edit, prize_params) do
    case Campaigns.update_prize(socket.assigns.prize, prize_params) do
      {:ok, _prize} ->
        notify_parent({:saved, :prize})

        {:noreply,
         socket
         |> put_flash(:info, "Prize updated successfully")
         |> push_patch(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_prize(socket, :new, prize_params) do
    prize_params = Map.put(prize_params, "campaign_id", socket.assigns.campaign.id)

    case Campaigns.create_prize(prize_params) do
      {:ok, _prize} ->
        notify_parent({:saved, :prize})

        {:noreply,
         socket
         |> put_flash(:info, "Prize created successfully")
         |> push_patch(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp prize_type_options do
    [
      {"Physical", "physical"},
      {"Virtual", "virtual"},
      {"No Prize", "no_prize"}
    ]
  end

  defp probability_mode_options do
    [
      {"Percentage", "percentage"},
      {"Quantity Based", "quantity_based"}
    ]
  end
end
