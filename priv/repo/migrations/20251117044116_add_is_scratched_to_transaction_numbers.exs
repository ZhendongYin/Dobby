defmodule Dobby.Repo.Migrations.AddIsScratchedToTransactionNumbers do
  use Ecto.Migration

  def change do
    alter table(:transaction_numbers) do
      add :is_scratched, :boolean, default: false, null: false
    end

    create index(:transaction_numbers, [:is_scratched])
  end
end
