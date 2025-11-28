defmodule DobbyWeb.Admin.SessionLive do
  use DobbyWeb, :live_view

  import Phoenix.Component

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: :admin))}
  end

  def handle_event("validate", %{"admin" => admin_params}, socket) do
    form =
      admin_params
      |> to_form(as: :admin)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Logged out successfully")
     |> redirect(to: "/admin/login", replace: true)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :admin}}>
      <div class="mx-auto max-w-sm">
        <div class="mt-24">
          <h1 class="text-3xl font-bold text-center mb-8">Admin Login</h1>

          <.form
            for={@form}
            id="login-form"
            action="/admin/session"
            method="post"
            phx-change="validate"
            class="space-y-6"
          >
            <.input
              field={@form[:email]}
              type="email"
              label="Email"
              placeholder="admin@example.com"
              required
            />

            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              required
            />

            <button
              type="submit"
              class="w-full rounded-lg bg-zinc-900 px-4 py-3 text-sm font-semibold text-white hover:bg-zinc-700 focus:outline-none focus:ring-2 focus:ring-zinc-900 focus:ring-offset-2"
            >
              Log in
            </button>
          </.form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
