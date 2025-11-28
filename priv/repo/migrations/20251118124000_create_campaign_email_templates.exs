defmodule Dobby.Repo.Migrations.CreateCampaignEmailTemplates do
  use Ecto.Migration

  def up do
    create table(:campaign_email_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :email_template_id,
          references(:email_templates, type: :binary_id, on_delete: :delete_all),
          null: false

      add :is_default, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:campaign_email_templates, [:campaign_id, :email_template_id],
             name: :campaign_email_templates_unique_pairs
           )

    create index(:campaign_email_templates, [:campaign_id, :is_default],
             name: :campaign_email_templates_default_idx
           )

    flush()

    migrate_existing_templates()

    alter table(:email_templates) do
      remove :campaign_id
      remove :is_default
    end
  end

  def down do
    alter table(:email_templates) do
      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all)
      add :is_default, :boolean, default: false, null: false
    end

    restore_template_assignments()

    drop table(:campaign_email_templates)
  end

  defp migrate_existing_templates do
    now = DateTime.utc_now()

    repo().transaction(fn ->
      assignments =
        repo().query!(
          """
          SELECT id, campaign_id, is_default, inserted_at, updated_at
          FROM email_templates
          WHERE campaign_id IS NOT NULL
          """,
          []
        ).rows

      rows =
        Enum.map(assignments, fn [template_id, campaign_id, is_default, inserted_at, updated_at] ->
          %{
            id: Ecto.UUID.generate() |> Ecto.UUID.dump!(),
            campaign_id: campaign_id,
            email_template_id: template_id,
            is_default: is_default,
            inserted_at: inserted_at || now,
            updated_at: updated_at || now
          }
        end)

      if rows != [] do
        repo().insert_all("campaign_email_templates", rows)
      end
    end)
  end

  defp restore_template_assignments do
    repo().transaction(fn ->
      assignments =
        repo().query!(
          """
          SELECT email_template_id, campaign_id, is_default
          FROM campaign_email_templates
          """,
          []
        ).rows

      Enum.each(assignments, fn [template_id, campaign_id, is_default] ->
        repo().query!(
          """
          UPDATE email_templates
          SET campaign_id = $1, is_default = $2
          WHERE id = $3
          """,
          [campaign_id, is_default, template_id]
        )
      end)
    end)
  end
end
