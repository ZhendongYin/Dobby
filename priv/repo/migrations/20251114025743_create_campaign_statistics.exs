defmodule Dobby.Repo.Migrations.CreateCampaignStatistics do
  use Ecto.Migration

  def change do
    create table(:campaign_statistics, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :total_participants, :integer, default: 0, null: false
      add :total_winners, :integer, default: 0, null: false
      add :total_no_prize, :integer, default: 0, null: false
      add :last_calculated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:campaign_statistics, [:campaign_id])
  end
end
