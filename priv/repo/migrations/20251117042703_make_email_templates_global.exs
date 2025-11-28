defmodule Dobby.Repo.Migrations.MakeEmailTemplatesGlobal do
  use Ecto.Migration

  def up do
    # Drop the foreign key constraint first
    drop constraint(:email_templates, "email_templates_campaign_id_fkey")

    # Make campaign_id nullable to allow global templates
    alter table(:email_templates) do
      modify :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: true
    end
  end

  def down do
    # Drop the foreign key constraint
    drop constraint(:email_templates, "email_templates_campaign_id_fkey")

    # Make campaign_id required again
    alter table(:email_templates) do
      modify :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: false
    end
  end
end
