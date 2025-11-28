defmodule Dobby.StatisticsTest do
  use Dobby.DataCase

  alias Dobby.{Accounts, Campaigns, Lottery, Statistics}

  setup do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "stats_admin#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Stats Admin #{unique}"
      })

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        "name" => "Stats Campaign #{unique}",
        "description" => "Description",
        "status" => "active",
        "starts_at" => DateTime.add(now, -3600, :second),
        "ends_at" => DateTime.add(now, 7200, :second),
        "admin_id" => admin.id,
        "enable_protection" => false,
        "protection_count" => 0
      })

    %{admin: admin, campaign: campaign}
  end

  describe "get_campaign_stats/1" do
    test "returns empty stats for campaign with no records", %{campaign: campaign} do
      stats = Statistics.get_campaign_stats(campaign.id)

      assert stats.total_entries == 0
      assert stats.unique_users == 0
      assert stats.prizes_issued == 0
      assert stats.conversion_rate == 0.0
    end

    test "calculates stats correctly", %{campaign: campaign} do
      # Create prizes
      {:ok, prize1} =
        Campaigns.create_prize(%{
          "name" => "Prize 1",
          "prize_type" => "physical",
          "campaign_id" => campaign.id,
          "probability_mode" => "percentage",
          "probability" => "50"
        })

      {:ok, prize2} =
        Campaigns.create_prize(%{
          "name" => "Prize 2",
          "prize_type" => "virtual",
          "prize_code" => "VIRTUAL-CODE-123",
          "campaign_id" => campaign.id,
          "probability_mode" => "percentage",
          "probability" => "30"
        })

      # Create transaction numbers
      {:ok, tx1} =
        Lottery.create_transaction_number(%{
          "transaction_number" => "TX1",
          "campaign_id" => campaign.id
        })

      {:ok, tx2} =
        Lottery.create_transaction_number(%{
          "transaction_number" => "TX2",
          "campaign_id" => campaign.id
        })

      {:ok, tx3} =
        Lottery.create_transaction_number(%{
          "transaction_number" => "TX3",
          "campaign_id" => campaign.id
        })

      # Create winning records
      {:ok, _wr1} =
        Lottery.create_winning_record(%{
          "transaction_number_id" => tx1.id,
          "prize_id" => prize1.id,
          "campaign_id" => campaign.id,
          "status" => "pending_process",
          "email" => "user1@example.com"
        })

      {:ok, _wr2} =
        Lottery.create_winning_record(%{
          "transaction_number_id" => tx2.id,
          "prize_id" => prize2.id,
          "campaign_id" => campaign.id,
          "status" => "fulfilled",
          # Same user
          "email" => "user1@example.com"
        })

      {:ok, _wr3} =
        Lottery.create_winning_record(%{
          "transaction_number_id" => tx3.id,
          "prize_id" => prize1.id,
          "campaign_id" => campaign.id,
          "status" => "expired",
          "email" => "user2@example.com"
        })

      stats = Statistics.get_campaign_stats(campaign.id)

      assert stats.total_entries == 3
      assert stats.unique_users == 2
      # pending_process + fulfilled
      assert stats.prizes_issued == 2
      assert stats.conversion_rate == Float.round(2 / 3 * 100, 1)
    end

    test "calculates conversion rate as 0 when no entries", %{campaign: campaign} do
      stats = Statistics.get_campaign_stats(campaign.id)
      assert stats.conversion_rate == 0.0
    end

    test "includes chart data", %{campaign: campaign} do
      stats = Statistics.get_campaign_stats(campaign.id)
      assert is_map(stats.entries_chart)
      assert is_map(stats.prize_chart)
      assert Map.has_key?(stats.entries_chart, :labels)
      assert Map.has_key?(stats.entries_chart, :datasets)
    end
  end

  describe "campaign_statistic crud" do
    test "list_campaign_statistics/0 returns all statistics" do
      assert Statistics.list_campaign_statistics() == []
    end

    test "get_campaign_statistic!/1 returns the statistic with given id", %{campaign: campaign} do
      {:ok, statistic} =
        Statistics.create_campaign_statistic(%{
          "campaign_id" => campaign.id,
          "total_participants" => 100,
          "total_winners" => 50
        })

      assert Statistics.get_campaign_statistic!(statistic.id) == statistic
    end

    test "create_campaign_statistic/1 with valid data creates a statistic", %{campaign: campaign} do
      assert {:ok, %Statistics.CampaignStatistic{} = statistic} =
               Statistics.create_campaign_statistic(%{
                 "campaign_id" => campaign.id,
                 "total_participants" => 100,
                 "total_winners" => 50
               })

      assert statistic.campaign_id == campaign.id
      assert statistic.total_participants == 100
      assert statistic.total_winners == 50
    end

    test "update_campaign_statistic/2 with valid data updates the statistic", %{
      campaign: campaign
    } do
      {:ok, statistic} =
        Statistics.create_campaign_statistic(%{
          "campaign_id" => campaign.id,
          "total_participants" => 100,
          "total_winners" => 50
        })

      assert {:ok, %Statistics.CampaignStatistic{} = statistic} =
               Statistics.update_campaign_statistic(statistic, %{"total_participants" => 200})

      assert statistic.total_participants == 200
    end

    test "delete_campaign_statistic/1 deletes the statistic", %{campaign: campaign} do
      {:ok, statistic} =
        Statistics.create_campaign_statistic(%{
          "campaign_id" => campaign.id,
          "total_participants" => 100,
          "total_winners" => 50
        })

      assert {:ok, %Statistics.CampaignStatistic{}} =
               Statistics.delete_campaign_statistic(statistic)

      assert_raise Ecto.NoResultsError, fn -> Statistics.get_campaign_statistic!(statistic.id) end
    end

    test "change_campaign_statistic/1 returns a changeset", %{campaign: campaign} do
      {:ok, statistic} =
        Statistics.create_campaign_statistic(%{
          "campaign_id" => campaign.id,
          "total_participants" => 100,
          "total_winners" => 50
        })

      assert %Ecto.Changeset{} = Statistics.change_campaign_statistic(statistic)
    end
  end
end
