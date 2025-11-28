defmodule Dobby.Repo.Migrations.CreateEmailTemplates do
  use Ecto.Migration

  def change do
    create table(:email_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :subject, :string, null: false
      add :html_content, :text, null: false
      add :text_content, :text
      add :variables, :jsonb
      add :is_default, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:email_templates, [:campaign_id])
    create index(:email_templates, [:is_default])
  end
end
