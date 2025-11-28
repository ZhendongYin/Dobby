defmodule Dobby.Repo.Migrations.RemoveEmailTemplateIdFromCampaigns do
  use Ecto.Migration

  def up do
    migrate_campaign_templates()

    drop_if_exists index(:campaigns, [:email_template_id])

    alter table(:campaigns) do
      remove :email_template_id
    end
  end

  def down do
    alter table(:campaigns) do
      add :email_template_id,
          references(:email_templates, type: :binary_id, on_delete: :nilify_all)
    end

    execute("""
    UPDATE campaigns AS c
    SET email_template_id = sub.email_template_id
    FROM (
      SELECT DISTINCT ON (campaign_id) campaign_id, email_template_id
      FROM campaign_email_templates
      WHERE is_default = true
      ORDER BY campaign_id, inserted_at DESC
    ) AS sub
    WHERE c.id = sub.campaign_id
    """)

    create index(:campaigns, [:email_template_id])
  end

  defp migrate_campaign_templates do
    repo().transaction(fn ->
      now = DateTime.utc_now()

      rows =
        repo()
        |> query_campaign_template_rows()
        |> Map.fetch!(:rows)
        |> Enum.map(fn [campaign_id, template_id, inserted_at, updated_at] ->
          %{
            id: Ecto.UUID.generate(),
            campaign_id: campaign_id,
            email_template_id: template_id,
            is_default: true,
            inserted_at: inserted_at || now,
            updated_at: updated_at || now
          }
        end)

      if rows != [] do
        repo().insert_all("campaign_email_templates", rows,
          on_conflict: :nothing,
          conflict_target: :campaign_email_templates_unique_pairs
        )
      end
    end)
  end

  defp query_campaign_template_rows(repo) do
    repo.query!("""
    SELECT id, email_template_id, inserted_at, updated_at
    FROM campaigns
    WHERE email_template_id IS NOT NULL
    """)
  end
end
