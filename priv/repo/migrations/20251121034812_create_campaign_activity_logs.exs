defmodule Dobby.Repo.Migrations.CreateCampaignActivityLogs do
  use Ecto.Migration

  def change do
    create table(:campaign_activity_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :admin_id, references(:admins, type: :binary_id, on_delete: :nilify_all)
      add :action, :string, null: false
      add :target_type, :string, null: false
      add :target_id, :binary_id
      add :field, :string
      add :from_value, :text
      add :to_value, :text
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create index(:campaign_activity_logs, [:campaign_id])
    create index(:campaign_activity_logs, [:admin_id])
    create index(:campaign_activity_logs, [:inserted_at])
    create index(:campaign_activity_logs, [:campaign_id, :inserted_at])
  end
end
