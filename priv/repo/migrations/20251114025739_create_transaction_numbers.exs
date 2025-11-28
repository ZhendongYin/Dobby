defmodule Dobby.Repo.Migrations.CreateTransactionNumbers do
  use Ecto.Migration

  def change do
    create table(:transaction_numbers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :transaction_number, :string, null: false

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :is_used, :boolean, default: false, null: false
      add :used_at, :utc_datetime
      add :ip_address, :string
      add :user_agent, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:transaction_numbers, [:transaction_number])
    create index(:transaction_numbers, [:campaign_id, :is_used])
    create index(:transaction_numbers, [:ip_address])
  end
end
