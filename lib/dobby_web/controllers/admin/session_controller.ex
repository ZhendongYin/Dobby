defmodule DobbyWeb.Admin.SessionController do
  use DobbyWeb, :controller

  alias Dobby.Accounts

  def create(conn, %{"admin" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_admin(email, password) do
      {:ok, admin} ->
        conn
        |> put_session(:admin_id, admin.id)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: "/admin")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: "/admin/login")
    end
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: "/admin/login")
  end
end
