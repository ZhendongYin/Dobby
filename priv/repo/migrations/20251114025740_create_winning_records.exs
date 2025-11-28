defmodule Dobby.Repo.Migrations.CreateWinningRecords do
  use Ecto.Migration

  def change do
    create table(:winning_records, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :transaction_number_id,
          references(:transaction_numbers, type: :binary_id, on_delete: :delete_all), null: false

      add :prize_id, references(:prizes, type: :binary_id, on_delete: :delete_all), null: false

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :email, :string
      add :name, :string
      add :phone, :string
      add :address, :text
      add :virtual_code, :string
      add :status, :string, default: "pending_submit", null: false
      add :email_sent, :boolean, default: false, null: false
      add :email_sent_at, :utc_datetime
      add :fulfilled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:winning_records, [:transaction_number_id])
    create index(:winning_records, [:prize_id])
    create index(:winning_records, [:campaign_id])
    create index(:winning_records, [:status])
    create index(:winning_records, [:email])
    create index(:winning_records, [:inserted_at])
  end
end
