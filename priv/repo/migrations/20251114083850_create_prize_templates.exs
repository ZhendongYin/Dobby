defmodule Dobby.Repo.Migrations.CreatePrizeTemplates do
  use Ecto.Migration

  def change do
    create table(:prize_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :prize_type, :string, null: false, default: "physical"
      add :image_url, :string
      add :description, :string
      add :redemption_guide, :text

      timestamps(type: :utc_datetime)
    end

    create index(:prize_templates, [:prize_type])
  end
end
