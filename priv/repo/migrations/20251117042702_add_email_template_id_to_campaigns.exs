defmodule Dobby.Repo.Migrations.AddEmailTemplateIdToCampaigns do
  use Ecto.Migration

  def change do
    alter table(:campaigns) do
      add :email_template_id,
          references(:email_templates, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:campaigns, [:email_template_id])
  end
end
