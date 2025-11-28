defmodule Dobby.Repo.Migrations.AddSourceTemplateToPrizes do
  use Ecto.Migration

  def change do
    alter table(:prizes) do
      add :source_template_id,
          references(:prize_templates, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:prizes, [:source_template_id])
  end
end
