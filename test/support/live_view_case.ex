defmodule DobbyWeb.LiveViewCase do
  @moduledoc """
  Shared setup for LiveView tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      use DobbyWeb, :verified_routes

      import DobbyWeb.LiveViewCase

      @endpoint DobbyWeb.Endpoint
    end
  end

  setup tags do
    Dobby.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Helper that registers and logs in an admin, returning the updated conn.
  """
  def register_and_log_in_admin(%{conn: conn}) do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Dobby.Accounts.register_admin(%{
        email: "admin#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Test Admin #{unique}"
      })

    conn =
      conn
      |> Phoenix.ConnTest.init_test_session(%{})
      |> Plug.Conn.put_session(:admin_id, admin.id)

    {:ok, conn: conn, admin: admin}
  end
end
