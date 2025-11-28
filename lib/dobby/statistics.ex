defmodule Dobby.Statistics do
  @moduledoc """
  The Statistics context.
  """

  import Ecto.Query, warn: false
  alias Dobby.Repo

  alias Dobby.Statistics.CampaignStatistic
  alias Dobby.Lottery.WinningRecord

  @doc """
  Returns the list of campaign_statistics.
  """
  def list_campaign_statistics do
    Repo.all(CampaignStatistic)
  end

  @doc """
  Gets a single campaign_statistic.

  Raises `Ecto.NoResultsError` if the Campaign statistic does not exist.
  """
  def get_campaign_statistic!(id), do: Repo.get!(CampaignStatistic, id)

  @doc """
  Creates a campaign_statistic.
  """
  def create_campaign_statistic(attrs \\ %{}) do
    %CampaignStatistic{}
    |> CampaignStatistic.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a campaign_statistic.
  """
  def update_campaign_statistic(%CampaignStatistic{} = campaign_statistic, attrs) do
    campaign_statistic
    |> CampaignStatistic.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a campaign_statistic.
  """
  def delete_campaign_statistic(%CampaignStatistic{} = campaign_statistic) do
    Repo.delete(campaign_statistic)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking campaign_statistic changes.
  """
  def change_campaign_statistic(%CampaignStatistic{} = campaign_statistic, attrs \\ %{}) do
    CampaignStatistic.changeset(campaign_statistic, attrs)
  end

  def get_campaign_stats(campaign_id) do
    total_entries =
      from(w in WinningRecord, where: w.campaign_id == ^campaign_id)
      |> Repo.aggregate(:count)

    unique_users =
      from(w in WinningRecord,
        where: w.campaign_id == ^campaign_id,
        select: count(fragment("distinct ?", w.email))
      )
      |> Repo.one()

    prizes_issued =
      from(w in WinningRecord,
        where: w.campaign_id == ^campaign_id and w.status in ["pending_process", "fulfilled"]
      )
      |> Repo.aggregate(:count)

    conversion_rate =
      if total_entries > 0 do
        Float.round(prizes_issued / total_entries * 100, 1)
      else
        0.0
      end

    %{
      total_entries: total_entries,
      unique_users: unique_users,
      prizes_issued: prizes_issued,
      conversion_rate: conversion_rate,
      entries_chart: mock_entries_chart(),
      prize_chart: mock_prize_chart()
    }
  end

  defp mock_entries_chart do
    today = Date.utc_today()

    %{
      labels:
        Enum.map(6..0//-1, fn offset ->
          today |> Date.add(-offset) |> Date.to_iso8601()
        end),
      datasets: [
        %{
          label: "Entries",
          data: Enum.map(1..7, fn day -> Enum.random(20..80) + day * 5 end)
        }
      ]
    }
  end

  defp mock_prize_chart do
    %{
      labels: ["Grand Prize", "Second Prize", "No Prize"],
      datasets: [
        %{
          data: [12, 25, 63]
        }
      ]
    }
  end
end
