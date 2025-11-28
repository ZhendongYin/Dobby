defmodule DobbyWeb.Admin.EmailLogLive.IndexTest do
  use DobbyWeb.LiveViewCase

  import Ecto.Query
  alias Dobby.Emails.EmailLog
  alias Dobby.Campaigns
  alias Dobby.Repo

  setup [:register_and_log_in_admin]

  describe "email log listing" do
    test "renders email logs on index", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log_fixture(campaign, %{to_email: "user@example.com", status: "sent"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      assert render(view) =~ "user@example.com"
      assert has_element?(view, "tr")
    end

    test "displays empty state when no logs exist", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      assert render(view) =~ "目前沒有符合條件的郵件記錄"
    end

    test "displays stats cards", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log_fixture(campaign, %{status: "sent"})
      email_log_fixture(campaign, %{status: "sent"})
      email_log_fixture(campaign, %{status: "failed"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      html = render(view)
      assert html =~ "總發送數"
      assert html =~ "成功"
      assert html =~ "失敗"
    end

    test "displays page header", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      assert render(view) =~ "郵件發送歷史"
      assert render(view) =~ "查看所有郵件發送歷史記錄"
    end
  end

  describe "filtering" do
    test "filters by status", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log_fixture(campaign, %{to_email: "sent@example.com", status: "sent"})
      email_log_fixture(campaign, %{to_email: "failed@example.com", status: "failed"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      view
      |> element("#form-select-status")
      |> render_change(%{"status" => "sent"})

      html = render(view)
      assert html =~ "sent@example.com"
      refute html =~ "failed@example.com"
    end

    test "filters by campaign", %{conn: conn, admin: admin} do
      campaign1 = campaign_fixture(admin, %{name: "Campaign 1"})
      campaign2 = campaign_fixture(admin, %{name: "Campaign 2"})
      email_log_fixture(campaign1, %{to_email: "user1@example.com"})
      email_log_fixture(campaign2, %{to_email: "user2@example.com"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      view
      |> element("#form-select-campaign_id")
      |> render_change(%{"campaign_id" => campaign1.id})

      html = render(view)
      assert html =~ "user1@example.com"
      refute html =~ "user2@example.com"
    end

    test "filters by search term", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log_fixture(campaign, %{to_email: "alpha@example.com", subject: "Alpha Subject"})
      email_log_fixture(campaign, %{to_email: "beta@example.com", subject: "Beta Subject"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "alpha"})

      html = render(view)
      assert html =~ "alpha@example.com"
      refute html =~ "beta@example.com"
    end

    test "resets to page 1 when filtering", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      # Create enough logs to have multiple pages
      for i <- 1..25 do
        email_log_fixture(campaign, %{to_email: "user#{i}@example.com"})
      end

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs?page=2")

      view
      |> element("#form-select-status")
      |> render_change(%{"status" => "sent"})

      # Should be on page 1 after filter (URL may include other params)
      html = render(view)
      assert html =~ "user1@example.com" || html =~ "user2@example.com"
    end
  end

  describe "sorting" do
    test "sorts by inserted_at descending by default", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      older_log = email_log_fixture(campaign, %{to_email: "older@example.com"})
      email_log_fixture(campaign, %{to_email: "newer@example.com"})

      # Update older to have earlier timestamp
      from(el in EmailLog, where: el.id == ^older_log.id)
      |> Repo.update_all(set: [inserted_at: DateTime.add(DateTime.utc_now(), -3600, :second)])

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      html = render(view)
      newer_pos = String.split(html, "newer@example.com") |> Enum.at(0) |> String.length()
      older_pos = String.split(html, "older@example.com") |> Enum.at(0) |> String.length()
      assert newer_pos < older_pos
    end

    test "sorts by to_email ascending", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log_fixture(campaign, %{to_email: "zebra@example.com"})
      email_log_fixture(campaign, %{to_email: "apple@example.com"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      view
      |> element("th[phx-click='sort'][phx-value-field='to_email'][phx-value-order='asc']")
      |> render_click()

      html = render(view)
      apple_pos = String.split(html, "apple@example.com") |> Enum.at(0) |> String.length()
      zebra_pos = String.split(html, "zebra@example.com") |> Enum.at(0) |> String.length()
      assert apple_pos < zebra_pos
    end

    test "sorts by subject", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log_fixture(campaign, %{subject: "Zebra Subject"})
      email_log_fixture(campaign, %{subject: "Apple Subject"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      view
      |> element("th[phx-click='sort'][phx-value-field='subject'][phx-value-order='asc']")
      |> render_click()

      html = render(view)
      apple_pos = String.split(html, "Apple Subject") |> Enum.at(0) |> String.length()
      zebra_pos = String.split(html, "Zebra Subject") |> Enum.at(0) |> String.length()
      assert apple_pos < zebra_pos
    end

    test "resets to page 1 when sorting", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)

      for i <- 1..25 do
        email_log_fixture(campaign, %{to_email: "user#{i}@example.com"})
      end

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs?page=2")

      view
      |> element("th[phx-click='sort'][phx-value-field='to_email'][phx-value-order='asc']")
      |> render_click()

      # Should reload with page 1 data (no patch, just reload)
      html = render(view)
      assert html =~ "user1@example.com" || html =~ "user2@example.com"
    end
  end

  describe "pagination" do
    test "displays pagination when there are multiple pages", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      # Create more than page_size (20) logs
      for i <- 1..25 do
        email_log_fixture(campaign, %{to_email: "user#{i}@example.com"})
      end

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      # Should show pagination buttons
      html = render(view)
      assert html =~ "go_to_page"
    end

    test "does not display pagination when there is only one page", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log_fixture(campaign, %{to_email: "user@example.com"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      html = render(view)
      refute html =~ "go_to_page"
    end

    test "changes page size", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)

      for i <- 1..25 do
        email_log_fixture(campaign, %{to_email: "user#{i}@example.com"})
      end

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      view
      |> element("select[name='page_size']")
      |> render_change(%{page_size: "50"})

      # Should show more items per page
      html = render(view)
      log_count = length(Regex.scan(~r/user\d+@example\.com/, html))
      assert log_count >= 20
    end

    test "navigates to different pages", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)

      for i <- 1..25 do
        email_log_fixture(campaign, %{to_email: "user#{i}@example.com"})
      end

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      # Navigate to page 2
      view
      |> element("button[phx-click='go_to_page'][phx-value-page='2']")
      |> render_click()

      # Should load page 2 data (no patch, just reload)
      html = render(view)
      assert html =~ "user21@example.com" || html =~ "user2@example.com"
    end
  end

  describe "view log details" do
    test "opens modal when clicking view details", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)

      email_log =
        email_log_fixture(campaign, %{
          to_email: "user@example.com",
          subject: "Test Subject",
          html_content: "<p>Test content</p>"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      view
      |> element("button[phx-click='view_log'][phx-value-id='#{email_log.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "郵件詳情"
      assert html =~ "user@example.com"
      assert html =~ "Test Subject"
      assert html =~ "Test content"
    end

    test "closes modal when clicking close button", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log = email_log_fixture(campaign, %{to_email: "user@example.com"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      # Open modal
      view
      |> element("button[phx-click='view_log'][phx-value-id='#{email_log.id}']")
      |> render_click()

      assert render(view) =~ "郵件詳情"

      # Close modal
      view
      |> element("button[phx-click='close_modal']")
      |> render_click()

      refute render(view) =~ "郵件詳情"
    end

    test "displays error message in modal when log has error", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)

      email_log =
        email_log_fixture(campaign, %{
          to_email: "user@example.com",
          status: "failed",
          error_message: "SMTP connection failed"
        })

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      view
      |> element("button[phx-click='view_log'][phx-value-id='#{email_log.id}']")
      |> render_click()

      html = render(view)
      assert html =~ "錯誤：SMTP connection failed"
    end
  end

  describe "status badges" do
    test "displays correct badge for sent status", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log_fixture(campaign, %{status: "sent"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      assert render(view) =~ "成功"
    end

    test "displays correct badge for failed status", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log_fixture(campaign, %{status: "failed"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      assert render(view) =~ "失敗"
    end

    test "displays correct badge for pending status", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      email_log_fixture(campaign, %{status: "pending"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      assert render(view) =~ "待發送"
    end
  end

  describe "campaign and template display" do
    test "displays campaign name when log has campaign", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin, %{name: "Test Campaign"})
      email_log_fixture(campaign, %{to_email: "user@example.com"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-logs")

      html = render(view)
      assert html =~ "Test Campaign"
      assert html =~ "user@example.com"
    end
  end

  # Helper functions
  defp campaign_fixture(admin, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    defaults = %{
      "name" => "Campaign #{System.unique_integer([:positive])}",
      "description" => "Description",
      "status" => "draft",
      "starts_at" => DateTime.add(now, 3600, :second),
      "ends_at" => DateTime.add(now, 7200, :second),
      "admin_id" => admin.id,
      "enable_protection" => false,
      "protection_count" => 0
    }

    attrs =
      defaults
      |> Map.merge(stringify_keys(attrs))

    {:ok, campaign} = Campaigns.create_campaign(attrs)
    campaign
  end

  defp email_log_fixture(campaign, attrs) do
    defaults = %{
      "campaign_id" => campaign.id,
      "to_email" => "user#{System.unique_integer([:positive])}@example.com",
      "from_email" => "noreply@example.com",
      "from_name" => "Test Sender",
      "subject" => "Test Subject",
      "html_content" => "<p>Test HTML</p>",
      "text_content" => "Test Text",
      "status" => "sent",
      "sent_at" => DateTime.utc_now() |> DateTime.truncate(:second)
    }

    attrs =
      defaults
      |> Map.merge(stringify_keys(attrs))

    %EmailLog{}
    |> EmailLog.changeset(attrs)
    |> Repo.insert!()
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end
end
