defmodule Dobby.Repo.Migrations.AddPrizeCodeToPrizes do
  use Ecto.Migration

  def change do
    alter table(:prizes) do
      add :prize_code, :string
    end
  end
end
