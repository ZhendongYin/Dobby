defmodule Dobby.Repo.Migrations.AllowNullForPrizeQuantities do
  use Ecto.Migration

  def up do
    alter table(:prizes) do
      modify :total_quantity, :integer, null: true, default: nil
      modify :remaining_quantity, :integer, null: true, default: nil
    end
  end

  def down do
    alter table(:prizes) do
      modify :total_quantity, :integer, null: false, default: 0
      modify :remaining_quantity, :integer, null: false, default: 0
    end
  end
end
