defmodule Dobby.Campaigns.Scheduler do
  @moduledoc """
  GenServer that periodically checks and updates campaign statuses
  based on their start and end dates.
  """
  use GenServer

  require Logger

  # Check every 1 minute
  @check_interval 60_000
  # Reset daily usage at 00:00 UTC (midnight)
  @daily_reset_hour 0
  @daily_reset_minute 0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    # Schedule the first check
    schedule_check()
    # Schedule daily reset
    schedule_daily_reset()
    {:ok, %{last_reset_date: today()}}
  end

  @impl true
  def handle_info(:check_campaigns, state) do
    Logger.info("Checking campaign statuses...")
    Dobby.Campaigns.update_campaign_statuses()
    # Schedule the next check
    schedule_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(:reset_daily_usage, state) do
    Logger.info("Resetting daily usage for all prizes...")
    Dobby.Campaigns.reset_all_prizes_daily_usage()
    schedule_daily_reset()
    {:noreply, Map.put(state, :last_reset_date, today())}
  end

  defp schedule_check do
    Process.send_after(self(), :check_campaigns, @check_interval)
  end

  defp schedule_daily_reset do
    now = DateTime.utc_now()

    # Calculate next reset time (midnight UTC)
    reset_time = %DateTime{
      year: now.year,
      month: now.month,
      day: now.day,
      hour: @daily_reset_hour,
      minute: @daily_reset_minute,
      second: 0,
      microsecond: {0, 6},
      std_offset: 0,
      utc_offset: 0,
      time_zone: "Etc/UTC",
      zone_abbr: "UTC"
    }

    # If reset time has passed today, schedule for tomorrow
    reset_time =
      if DateTime.compare(now, reset_time) == :gt do
        DateTime.add(reset_time, 1, :day)
      else
        reset_time
      end

    milliseconds_until_reset = DateTime.diff(reset_time, now, :millisecond)

    Process.send_after(self(), :reset_daily_usage, milliseconds_until_reset)
  end

  defp today do
    DateTime.utc_now() |> DateTime.to_date()
  end
end
