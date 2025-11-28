defmodule Dobby.Repo.Migrations.CreateCampaigns do
  use Ecto.Migration

  def change do
    create table(:campaigns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :status, :string, default: "draft", null: false
      add :starts_at, :utc_datetime, null: false
      add :ends_at, :utc_datetime, null: false
      add :background_image_url, :string
      add :theme_color, :string
      add :no_prize_message, :string
      add :rules_text, :text
      add :enable_protection, :boolean, default: false, null: false
      add :protection_count, :integer, default: 0, null: false
      add :admin_id, references(:admins, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:campaigns, [:status])
    create index(:campaigns, [:starts_at, :ends_at])
    create index(:campaigns, [:admin_id])
  end
end
