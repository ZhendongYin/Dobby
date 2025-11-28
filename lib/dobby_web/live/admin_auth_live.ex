defmodule DobbyWeb.AdminAuthLive do
  @moduledoc """
  LiveView hook for admin authentication.
  """
  import Phoenix.LiveView
  alias Dobby.Accounts

  def on_mount(:default, _params, session, socket) do
    current_admin =
      if admin_id = session["admin_id"] do
        try do
          Accounts.get_admin!(admin_id)
        rescue
          Ecto.NoResultsError -> nil
        end
      end

    socket = Phoenix.Component.assign(socket, :current_admin, current_admin)

    if current_admin do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/admin/login")}
    end
  end
end
