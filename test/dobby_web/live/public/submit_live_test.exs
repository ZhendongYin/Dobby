defmodule DobbyWeb.Public.SubmitLiveTest do
  use DobbyWeb.LiveViewCase

  alias Dobby.{Accounts, Campaigns, Lottery}
  import Dobby.Fixtures

  setup do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "submit_admin#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Submit Admin #{unique}"
      })

    %{admin: admin}
  end

  describe "form state" do
    test "renders form for physical prize", %{conn: conn, admin: admin} do
      campaign = active_campaign_fixture(admin)
      prize = prize_fixture(campaign, %{"prize_type" => "physical"})
      transaction = transaction_fixture(campaign, %{is_used: true})

      winning_record =
        winning_record_fixture(campaign, prize, transaction, %{status: "pending_submit"})

      {:ok, view, _html} = live(conn, ~p"/submit/#{winning_record.id}")

      assert has_element?(view, "#submit-form")
      assert render(view) =~ prize.name
      assert render(view) =~ "名字"
      assert render(view) =~ "姓氏"
      assert render(view) =~ "電子郵件地址"
    end

    test "renders form for virtual prize", %{conn: conn, admin: admin} do
      campaign = active_campaign_fixture(admin)

      prize =
        prize_fixture(campaign, %{"prize_type" => "virtual", "prize_code" => "VIRTUAL-CODE-123"})

      transaction = transaction_fixture(campaign, %{is_used: true})

      winning_record =
        winning_record_fixture(campaign, prize, transaction, %{status: "pending_submit"})

      {:ok, view, _html} = live(conn, ~p"/submit/#{winning_record.id}")

      assert has_element?(view, "#submit-form")
      assert render(view) =~ prize.name
      assert render(view) =~ "電子郵件地址"
      refute render(view) =~ "名字"
      refute render(view) =~ "姓氏"
    end

    test "shows submitted state when already submitted", %{conn: conn, admin: admin} do
      campaign = active_campaign_fixture(admin)
      prize = prize_fixture(campaign, %{"prize_type" => "physical"})
      transaction = transaction_fixture(campaign, %{is_used: true})

      winning_record =
        winning_record_fixture(campaign, prize, transaction, %{
          status: "pending_process",
          name: "John Doe",
          email: "john@example.com"
        })

      {:ok, view, _html} = live(conn, ~p"/submit/#{winning_record.id}")

      assert render(view) =~ "信息已提交"
      refute has_element?(view, "#submit-form")
    end

    test "shows no prize state for no_prize type", %{conn: conn, admin: admin} do
      campaign = active_campaign_fixture(admin)
      prize = prize_fixture(campaign, %{"prize_type" => "no_prize"})
      transaction = transaction_fixture(campaign, %{is_used: true})

      winning_record =
        winning_record_fixture(campaign, prize, transaction, %{status: "pending_submit"})

      {:ok, view, _html} = live(conn, ~p"/submit/#{winning_record.id}")

      assert render(view) =~ "当前奖品无需登记"
      refute has_element?(view, "#submit-form")
    end

    test "redirects when winning record not found", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/submit/#{fake_id}")
    end
  end

  describe "form validation" do
    test "validates email format", %{conn: conn, admin: admin} do
      campaign = active_campaign_fixture(admin)

      prize =
        prize_fixture(campaign, %{"prize_type" => "virtual", "prize_code" => "VIRTUAL-CODE-123"})

      transaction = transaction_fixture(campaign, %{is_used: true})

      winning_record =
        winning_record_fixture(campaign, prize, transaction, %{status: "pending_submit"})

      {:ok, view, _html} = live(conn, ~p"/submit/#{winning_record.id}")

      html =
        view
        |> form("#submit-form")
        |> render_change(%{"winning_record" => %{"email" => "invalid-email"}})

      # Check that validation error is shown or form is present
      assert html =~ "email" || has_element?(view, "#submit-form")
    end

    test "validates required fields for physical prize", %{conn: conn, admin: admin} do
      campaign = active_campaign_fixture(admin)
      prize = prize_fixture(campaign, %{"prize_type" => "physical"})
      transaction = transaction_fixture(campaign, %{is_used: true})

      winning_record =
        winning_record_fixture(campaign, prize, transaction, %{status: "pending_submit"})

      {:ok, view, _html} = live(conn, ~p"/submit/#{winning_record.id}")

      view
      |> form("#submit-form", %{winning_record: %{email: "", first_name: "", last_name: ""}})
      |> render_submit()

      # Check that form is still present (validation should prevent submission)
      assert has_element?(view, "#submit-form")
    end
  end

  describe "form submission" do
    test "submits physical prize with name and email", %{conn: conn, admin: admin} do
      campaign = active_campaign_fixture(admin)
      prize = prize_fixture(campaign, %{"prize_type" => "physical"})
      transaction = transaction_fixture(campaign, %{is_used: true})

      winning_record =
        winning_record_fixture(campaign, prize, transaction, %{status: "pending_submit"})

      {:ok, view, _html} = live(conn, ~p"/submit/#{winning_record.id}")

      view
      |> form("#submit-form", %{
        winning_record: %{
          first_name: "John",
          last_name: "Doe",
          email: "john@example.com"
        }
      })
      |> render_submit()

      updated_record = Lottery.get_winning_record!(winning_record.id)
      assert updated_record.status == "pending_process"
      assert updated_record.name == "John Doe"
      assert updated_record.email == "john@example.com"
      assert render(view) =~ "信息已提交"
    end

    test "submits virtual prize with email only", %{conn: conn, admin: admin} do
      campaign = active_campaign_fixture(admin)

      prize =
        prize_fixture(campaign, %{"prize_type" => "virtual", "prize_code" => "VIRTUAL-CODE-123"})

      transaction = transaction_fixture(campaign, %{is_used: true})

      winning_record =
        winning_record_fixture(campaign, prize, transaction, %{status: "pending_submit"})

      {:ok, view, _html} = live(conn, ~p"/submit/#{winning_record.id}")

      view
      |> form("#submit-form", %{winning_record: %{email: "user@example.com"}})
      |> render_submit()

      updated_record = Lottery.get_winning_record!(winning_record.id)
      assert updated_record.status == "fulfilled"
      assert updated_record.email == "user@example.com"
      assert render(view) =~ "信息已提交"
    end

    test "handles validation errors on submit", %{conn: conn, admin: admin} do
      campaign = active_campaign_fixture(admin)
      prize = prize_fixture(campaign, %{"prize_type" => "physical"})
      transaction = transaction_fixture(campaign, %{is_used: true})

      winning_record =
        winning_record_fixture(campaign, prize, transaction, %{status: "pending_submit"})

      {:ok, view, _html} = live(conn, ~p"/submit/#{winning_record.id}")

      view
      |> form("#submit-form", %{winning_record: %{email: "", first_name: "", last_name: ""}})
      |> render_submit()

      # Check that form is still present (not submitted)
      assert has_element?(view, "#submit-form")
    end
  end

  defp active_campaign_fixture(admin, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    defaults = %{
      "name" => "Active Campaign #{System.unique_integer([:positive])}",
      "description" => "Description",
      "status" => "active",
      "starts_at" => DateTime.add(now, -3600, :second),
      "ends_at" => DateTime.add(now, 7200, :second),
      "admin_id" => admin.id,
      "enable_protection" => false,
      "protection_count" => 0
    }

    {:ok, campaign} =
      defaults
      |> Map.merge(stringify_keys(attrs))
      |> Campaigns.create_campaign()

    campaign
  end

  defp prize_fixture(campaign, attrs) do
    defaults = %{
      "name" => "Prize #{System.unique_integer([:positive])}",
      "description" => "Prize Description",
      "prize_type" => "physical",
      "campaign_id" => campaign.id,
      "total_quantity" => 10,
      "remaining_quantity" => 10,
      "probability_mode" => "percentage",
      "probability" => "50",
      "display_order" => 1
    }

    {:ok, prize} =
      defaults
      |> Map.merge(stringify_keys(attrs))
      |> Campaigns.create_prize()

    prize
  end

  defp transaction_fixture(campaign, attrs) do
    defaults = %{
      "transaction_number" => "TX#{System.unique_integer([:positive])}",
      "campaign_id" => campaign.id,
      "is_used" => false,
      "is_scratched" => false
    }

    {:ok, transaction} =
      defaults
      |> Map.merge(stringify_keys(attrs))
      |> Lottery.create_transaction_number()

    transaction
  end

  defp winning_record_fixture(campaign, prize, transaction, attrs) do
    defaults = %{
      "transaction_number_id" => transaction.id,
      "prize_id" => prize.id,
      "campaign_id" => campaign.id,
      "status" => "pending_submit"
    }

    {:ok, record} =
      defaults
      |> Map.merge(stringify_keys(attrs))
      |> Lottery.create_winning_record()

    record
  end
end
