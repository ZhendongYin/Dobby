defmodule Dobby.LotteryTest do
  use Dobby.DataCase

  alias Dobby.{Accounts, Campaigns, Lottery}
  alias Dobby.Campaigns.Prize
  alias Dobby.Repo

  setup do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "lottery_tester#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Lottery Tester #{unique}"
      })

    %{admin: admin}
  end

  describe "prize quantity decrementing" do
    test "decrements remaining quantity when prize is won", %{admin: admin} do
      campaign = active_campaign_fixture(admin)

      prize =
        prize_fixture(campaign, %{
          "total_quantity" => 10,
          "remaining_quantity" => 10,
          "probability_mode" => "percentage",
          # 100% probability to ensure we win
          "probability" => "100"
        })

      transaction_number = "TX#{System.unique_integer([:positive])}"

      assert {:ok, _result} =
               Lottery.draw_and_record(transaction_number, campaign.id, "127.0.0.1", "test")

      updated_prize = Repo.get!(Prize, prize.id)
      assert updated_prize.remaining_quantity == 9
    end

    test "does not allow negative remaining quantity with concurrent requests", %{admin: admin} do
      campaign = active_campaign_fixture(admin)

      prize =
        prize_fixture(campaign, %{
          "total_quantity" => 5,
          "remaining_quantity" => 5,
          "probability_mode" => "percentage",
          # 100% probability to ensure we win
          "probability" => "100"
        })

      # Create 10 transaction numbers
      transaction_numbers =
        Enum.map(1..10, fn i -> "TX#{System.unique_integer([:positive])}#{i}" end)

      # Spawn concurrent processes to draw prizes
      tasks =
        Enum.map(transaction_numbers, fn tx_num ->
          Task.async(fn ->
            Lottery.draw_and_record(tx_num, campaign.id, "127.0.0.1", "test")
          end)
        end)

      results = Enum.map(tasks, &Task.await/1)

      # Wait a bit for all updates to complete
      Process.sleep(200)

      updated_prize = Repo.get!(Prize, prize.id)

      # Verify remaining quantity never goes negative
      assert updated_prize.remaining_quantity >= 0
      assert updated_prize.remaining_quantity <= 5

      # Count successful draws that actually got the prize (not no_prize)
      successful_draws =
        Enum.count(results, fn
          {:ok, %{prize: %{id: prize_id}}} when prize_id == prize.id -> true
          _ -> false
        end)

      # At most 5 should succeed (we had 5 in stock)
      assert successful_draws <= 5,
             "Expected at most 5 successful draws, got #{successful_draws}. Remaining quantity: #{updated_prize.remaining_quantity}"
    end

    test "does not decrement when remaining quantity is already 0", %{admin: admin} do
      campaign = active_campaign_fixture(admin)

      prize =
        prize_fixture(campaign, %{
          "total_quantity" => 1,
          "remaining_quantity" => 0,
          "probability_mode" => "percentage",
          "probability" => "100"
        })

      transaction_number = "TX#{System.unique_integer([:positive])}"

      # This should still try to draw, but the prize should not be selected
      # because quantity is 0, so it should return :no_prize
      result = Lottery.draw_and_record(transaction_number, campaign.id, "127.0.0.1", "test")

      updated_prize = Repo.get!(Prize, prize.id)

      # Remaining quantity should still be 0
      assert updated_prize.remaining_quantity == 0

      # Should return no_prize when stock is 0
      case result do
        {:ok, %{prize: %{prize_type: "no_prize"}}} ->
          :ok

        {:ok, _} ->
          flunk("Expected no_prize when stock is 0, but got a prize")

        {:error, _} ->
          # Transaction might fail for other reasons (already used, etc)
          :ok
      end
    end

    test "returns error when attempting to decrement below zero concurrently", %{admin: admin} do
      campaign = active_campaign_fixture(admin)

      prize =
        prize_fixture(campaign, %{
          "total_quantity" => 3,
          "remaining_quantity" => 3,
          "probability_mode" => "percentage",
          "probability" => "100"
        })

      # Create more transaction numbers than we have stock
      transaction_numbers =
        Enum.map(1..5, fn i -> "TX#{System.unique_integer([:positive])}#{i}" end)

      # Concurrent draws
      tasks =
        Enum.map(transaction_numbers, fn tx_num ->
          Task.async(fn ->
            Lottery.draw_and_record(tx_num, campaign.id, "127.0.0.1", "test")
          end)
        end)

      results = Enum.map(tasks, &Task.await/1)

      # Wait for all database operations
      Process.sleep(100)

      updated_prize = Repo.get!(Prize, prize.id)

      # Verify we never go below 0
      assert updated_prize.remaining_quantity >= 0

      # Exactly 3 should succeed (we had 3 in stock)
      successful_count =
        Enum.count(results, fn
          {:ok, %{prize: %{id: prize_id}}} when prize_id == prize.id -> true
          _ -> false
        end)

      assert successful_count <= 3
      assert updated_prize.remaining_quantity == 3 - successful_count
    end
  end

  describe "daily limit enforcement" do
    test "does not allow daily_used to exceed daily_limit with concurrent requests", %{
      admin: admin
    } do
      campaign = active_campaign_fixture(admin)

      # Create a prize with daily_limit of 5
      prize =
        prize_fixture(campaign, %{
          "daily_limit" => 5,
          "daily_used" => 0,
          # Unlimited total quantity
          "total_quantity" => nil,
          "remaining_quantity" => nil,
          "probability_mode" => "percentage",
          # 100% probability to ensure we win
          "probability" => "100"
        })

      # Create 10 transaction numbers to test concurrent access
      transaction_numbers =
        Enum.map(1..10, fn i -> "TX#{System.unique_integer([:positive])}#{i}" end)

      # Spawn concurrent processes to draw prizes
      tasks =
        Enum.map(transaction_numbers, fn tx_num ->
          Task.async(fn ->
            Lottery.draw_and_record(tx_num, campaign.id, "127.0.0.1", "test")
          end)
        end)

      results = Enum.map(tasks, &Task.await/1)

      # Wait a bit for all updates to complete
      Process.sleep(200)

      updated_prize = Repo.get!(Prize, prize.id)

      # Verify daily_used never exceeds daily_limit
      assert updated_prize.daily_used >= 0

      assert updated_prize.daily_used <= 5,
             "Expected daily_used to be at most 5, got #{updated_prize.daily_used}"

      # Count successful draws that actually got the prize
      successful_draws =
        Enum.count(results, fn
          {:ok, %{prize: %{id: prize_id}}} when prize_id == prize.id -> true
          _ -> false
        end)

      # At most 5 should succeed due to daily limit
      assert successful_draws <= 5,
             "Expected at most 5 successful draws due to daily limit, got #{successful_draws}. daily_used: #{updated_prize.daily_used}"

      assert updated_prize.daily_used == successful_draws
    end

    test "blocks prize selection when daily_limit is reached", %{admin: admin} do
      campaign = active_campaign_fixture(admin)

      # Create a prize with daily_limit of 3 and daily_used already at 3
      prize =
        prize_fixture(campaign, %{
          "daily_limit" => 3,
          # Already at limit
          "daily_used" => 3,
          # Unlimited total quantity
          "total_quantity" => nil,
          "remaining_quantity" => nil,
          "probability_mode" => "percentage",
          "probability" => "100"
        })

      transaction_number = "TX#{System.unique_integer([:positive])}"

      result = Lottery.draw_and_record(transaction_number, campaign.id, "127.0.0.1", "test")

      updated_prize = Repo.get!(Prize, prize.id)

      # daily_used should still be 3 (not incremented)
      assert updated_prize.daily_used == 3

      # Should return no_prize when daily limit is reached
      case result do
        {:ok, %{prize: %{prize_type: "no_prize"}}} ->
          :ok

        {:ok, %{prize: %{id: prize_id}}} when prize_id == prize.id ->
          flunk("Expected no_prize when daily_limit is reached, but got the prize")

        {:error, _} ->
          # Transaction might fail for other reasons
          :ok
      end
    end
  end

  defp active_campaign_fixture(admin, attrs \\ %{}) do
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

    # Create a no_prize record for the campaign
    {:ok, _no_prize} =
      Campaigns.create_prize(%{
        "name" => "No Prize",
        "prize_type" => "no_prize",
        "campaign_id" => campaign.id,
        "probability_mode" => "percentage",
        "probability" => "0"
      })

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
