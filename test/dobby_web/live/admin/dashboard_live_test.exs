defmodule DobbyWeb.Admin.DashboardLiveTest do
  use DobbyWeb.LiveViewCase

  import Dobby.Fixtures, only: [campaign_fixture: 2]

  setup [:register_and_log_in_admin]

  describe "dashboard overview" do
    test "does not render Control Center hero section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      html = render(view)

      # Check that Control Center hero section (gradient background) is not present
      refute html =~ "bg-gradient-to-r from-indigo-600 via-purple-500 to-orange-400"
      refute html =~ "建立新活動"
      refute html =~ "Campaign Cockpit"
      # Header may still contain "Control Center", so we check for hero section specifically
      refute html =~ "你的活動正在全球同步運行"
    end

    test "does not render hero message in dashboard content", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin")
      html = render(view)

      # Check that hero message content is not in the dashboard
      refute html =~ "掌握中獎通知、用戶數據與待辦事項"
    end

    test "shows KPI cards and spotlight data when campaigns exist", %{conn: conn, admin: admin} do
      campaign_fixture(admin, %{status: "active", name: "Summer Promo"})

      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "進行中活動"
      assert html =~ "Campaign Spotlight"
      assert html =~ "Live Pulse"
      assert html =~ "營運待辦"
      assert html =~ "通知 / 警示"
    end
  end
end
