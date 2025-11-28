defmodule Dobby.Repo.Migrations.AddEmailTemplateToPrizes do
  use Ecto.Migration

  def change do
    alter table(:prizes) do
      add :email_template_id,
          references(:email_templates, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:prizes, [:email_template_id])
  end
end
