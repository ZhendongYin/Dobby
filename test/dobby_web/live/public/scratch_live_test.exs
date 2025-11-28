defmodule DobbyWeb.Public.ScratchLiveTest do
  use DobbyWeb.LiveViewCase

  alias Dobby.{Accounts, Campaigns, Lottery}

  setup do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "scratch_admin#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Scratch Admin #{unique}"
      })

    %{admin: admin}
  end

  describe "scratch flow" do
    test "renders scratch card and updates progress", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      prize = prize_fixture(campaign)
      transaction = transaction_fixture(campaign, %{is_used: true, is_scratched: false})
      winning_record_fixture(campaign, prize, transaction, %{status: "pending_submit"})
      refute transaction.is_scratched

      {:ok, view, _html} =
        live(conn, ~p"/campaigns/#{campaign.id}/scratch/#{transaction.transaction_number}")

      assert has_element?(view, "#scratch-card")
      assert render(view) =~ "刮开进度"

      render_hook(view, "update_progress", %{"progress" => "0.8"})

      assert Lottery.get_transaction_number!(transaction.id).is_scratched
      assert render(view) =~ "填写领奖信息"
    end

    test "shows already used message for redeemed codes", %{conn: conn, admin: admin} do
      campaign = campaign_fixture(admin)
      prize = prize_fixture(campaign)
      transaction = transaction_fixture(campaign, %{is_used: true, is_scratched: true})
      winning_record_fixture(campaign, prize, transaction, %{status: "fulfilled"})
      assert transaction.is_scratched

      {:ok, view, _html} =
        live(conn, ~p"/campaigns/#{campaign.id}/scratch/#{transaction.transaction_number}")

      assert render(view) =~ "券码已使用"
      assert render(view) =~ prize.name
    end

    test "redirects when transaction belongs to another campaign", %{conn: conn, admin: admin} do
      campaign_a = campaign_fixture(admin)
      campaign_b = campaign_fixture(admin, %{name: "Other Campaign"})
      transaction = transaction_fixture(campaign_b, %{is_used: true})

      assert {:error, {:redirect, %{to: "/"}}} =
               live(
                 conn,
                 ~p"/campaigns/#{campaign_a.id}/scratch/#{transaction.transaction_number}"
               )
    end
  end

  defp campaign_fixture(admin, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    defaults = %{
      "name" => "Scratch Campaign #{System.unique_integer([:positive])}",
      "description" => "Scratch and win!",
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

  defp prize_fixture(campaign, attrs \\ %{}) do
    defaults = %{
      "name" => "Grand Prize #{System.unique_integer([:positive])}",
      "description" => "Top tier prize",
      "prize_type" => "physical",
      "campaign_id" => campaign.id,
      "total_quantity" => 10,
      "remaining_quantity" => 10,
      "probability_mode" => "percentage",
      "probability" => "50",
      "weight" => 1,
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

  defp stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end
end
