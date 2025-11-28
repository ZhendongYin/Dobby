defmodule Dobby.Statistics.CampaignStatistic do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "campaign_statistics" do
    field :total_participants, :integer, default: 0
    field :total_winners, :integer, default: 0
    field :total_no_prize, :integer, default: 0
    field :last_calculated_at, :utc_datetime

    belongs_to :campaign, Dobby.Campaigns.Campaign

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(campaign_statistic, attrs) do
    campaign_statistic
    |> cast(attrs, [
      :total_participants,
      :total_winners,
      :total_no_prize,
      :last_calculated_at,
      :campaign_id
    ])
    |> validate_required([:campaign_id])
    |> unique_constraint(:campaign_id)
  end
end
