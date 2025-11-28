defmodule Dobby.Repo.Migrations.CreatePrizes do
  use Ecto.Migration

  def change do
    create table(:prizes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :description, :text
      add :image_url, :string
      add :prize_type, :string, null: false
      add :total_quantity, :integer, default: 0, null: false
      add :remaining_quantity, :integer, default: 0, null: false
      add :daily_limit, :integer
      add :daily_used, :integer, default: 0, null: false
      add :probability_mode, :string, default: "percentage", null: false
      add :probability, :decimal, precision: 5, scale: 2
      add :weight, :integer
      add :is_protected, :boolean, default: false, null: false
      add :redemption_guide, :text
      add :display_order, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:prizes, [:campaign_id])
    create index(:prizes, [:prize_type])
    create index(:prizes, [:display_order])
    create index(:prizes, [:is_protected])
  end
end
