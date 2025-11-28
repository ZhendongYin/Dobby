defmodule DobbyWeb.Admin.SessionControllerTest do
  use DobbyWeb.ConnCase, async: true

  alias Dobby.Accounts

  describe "POST /admin/session" do
    test "logs in admin with valid credentials", %{conn: conn} do
      unique = System.unique_integer([:positive])
      password = "Adm1nPass!#{unique}"

      {:ok, admin} =
        Accounts.register_admin(%{
          email: "admin#{unique}@example.com",
          password: password,
          name: "Admin #{unique}"
        })

      conn =
        post(conn, ~p"/admin/session", %{
          "admin" => %{"email" => admin.email, "password" => password}
        })

      conn = Phoenix.Controller.fetch_flash(conn)

      assert get_session(conn, :admin_id) == admin.id
      assert redirected_to(conn) == ~p"/admin"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Welcome back!"
    end

    test "shows error with invalid credentials", %{conn: conn} do
      unique = System.unique_integer([:positive])

      {:ok, admin} =
        Accounts.register_admin(%{
          email: "admin#{unique}@example.com",
          password: "Adm1nPass!#{unique}",
          name: "Admin #{unique}"
        })

      conn =
        post(conn, ~p"/admin/session", %{
          "admin" => %{"email" => admin.email, "password" => "wrong-pass"}
        })

      conn = Phoenix.Controller.fetch_flash(conn)

      assert get_session(conn, :admin_id) == nil
      assert redirected_to(conn) == ~p"/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
    end
  end

  describe "DELETE /admin/session" do
    test "logs out admin and clears session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{admin_id: "some-id"})
        |> delete(~p"/admin/session")
        |> Phoenix.Controller.fetch_flash()

      assert get_session(conn, :admin_id) == nil
      assert redirected_to(conn) == ~p"/admin/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Logged out successfully"
    end
  end
end
