defmodule Dobby.Campaigns.SchedulerTest do
  use Dobby.DataCase

  alias Dobby.{Accounts, Campaigns}
  alias Dobby.Campaigns.Prize
  alias Dobby.Campaigns.Scheduler
  alias Dobby.Repo

  setup do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "scheduler_tester#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Scheduler Tester #{unique}"
      })

    %{admin: admin}
  end

  describe "daily usage reset" do
    test "resets daily_used for all prizes with daily_limit", %{admin: admin} do
      campaign = campaign_fixture(admin)

      # Create prizes with daily limits and usage
      prize1 =
        prize_fixture(campaign, %{
          "daily_limit" => 10,
          "daily_used" => 5
        })

      prize2 =
        prize_fixture(campaign, %{
          "daily_limit" => 20,
          "daily_used" => 15
        })

      # Prize without daily limit should not be affected
      prize3 =
        prize_fixture(campaign, %{
          "daily_limit" => nil,
          "daily_used" => 3
        })

      # Reset daily usage
      Campaigns.reset_all_prizes_daily_usage()

      # Reload prizes
      prize1 = Repo.get!(Prize, prize1.id)
      prize2 = Repo.get!(Prize, prize2.id)
      prize3 = Repo.get!(Prize, prize3.id)

      # Prizes with daily_limit should be reset to 0
      assert prize1.daily_used == 0
      assert prize2.daily_used == 0

      # Prize without daily_limit should remain unchanged
      assert prize3.daily_used == 3
    end

    test "resets daily_used to 0 even when already 0", %{admin: admin} do
      campaign = campaign_fixture(admin)

      prize =
        prize_fixture(campaign, %{
          "daily_limit" => 10,
          "daily_used" => 0
        })

      Campaigns.reset_all_prizes_daily_usage()

      prize = Repo.get!(Prize, prize.id)
      assert prize.daily_used == 0
    end

    test "only resets prizes with daily_limit > 0", %{admin: admin} do
      campaign = campaign_fixture(admin)

      prize1 =
        prize_fixture(campaign, %{
          "daily_limit" => 0,
          "daily_used" => 5
        })

      prize2 =
        prize_fixture(campaign, %{
          "daily_limit" => nil,
          "daily_used" => 5
        })

      Campaigns.reset_all_prizes_daily_usage()

      prize1 = Repo.get!(Prize, prize1.id)
      prize2 = Repo.get!(Prize, prize2.id)

      # daily_limit of 0 or nil should not be reset
      assert prize1.daily_used == 5
      assert prize2.daily_used == 5
    end
  end

  describe "scheduler integration" do
    test "scheduler can handle reset_daily_usage message", %{admin: admin} do
      # Create a prize with daily usage
      campaign = campaign_fixture(admin)

      prize =
        prize_fixture(campaign, %{
          "daily_limit" => 10,
          "daily_used" => 5
        })

      # Get the existing scheduler process (it should already be running)
      # or handle the case where it's already started
      case GenServer.whereis(Scheduler) do
        nil ->
          # Not running, start it
          {:ok, pid} = Scheduler.start_link([])
          send(pid, :reset_daily_usage)
          Process.sleep(100)
          assert Process.alive?(pid)
          GenServer.stop(pid)

        pid ->
          # Already running, just send the message
          send(pid, :reset_daily_usage)
          Process.sleep(100)
          # Verify the reset worked
          prize = Repo.get!(Prize, prize.id)
          assert prize.daily_used == 0
      end
    end
  end

  defp campaign_fixture(admin, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    defaults = %{
      "name" => "Test Campaign #{System.unique_integer([:positive])}",
      "description" => "Test Description",
      "status" => "active",
      "starts_at" => DateTime.add(now, -3600, :second),
      "ends_at" => DateTime.add(now, 7200, :second),
      "admin_id" => admin.id,
      "enable_protection" => false,
      "protection_count" => 0
    }

    {:ok, campaign} =
      defaults
      |> Map.merge(Dobby.Fixtures.stringify_keys(attrs))
      |> Campaigns.create_campaign()

    campaign
  end

  defp prize_fixture(campaign, attrs) do
    defaults = %{
      "name" => "Test Prize #{System.unique_integer([:positive])}",
      "description" => "Test Prize Description",
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
      |> Map.merge(Dobby.Fixtures.stringify_keys(attrs))
      |> Campaigns.create_prize()

    prize
  end
end
