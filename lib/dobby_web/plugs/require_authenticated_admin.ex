defmodule DobbyWeb.Plugs.RequireAuthenticatedAdmin do
  @moduledoc """
  Ensures that an admin is authenticated.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Dobby.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    current_admin =
      if admin_id = get_session(conn, :admin_id) do
        try do
          Accounts.get_admin!(admin_id)
        rescue
          Ecto.NoResultsError -> nil
        end
      end

    if current_admin do
      assign(conn, :current_admin, current_admin)
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: "/admin/login")
      |> halt()
    end
  end
end
