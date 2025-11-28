defmodule Dobby.Repo.Migrations.CreateEmailLogs do
  use Ecto.Migration

  def change do
    create table(:email_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :winning_record_id,
          references(:winning_records, type: :binary_id, on_delete: :nilify_all)

      add :campaign_id, references(:campaigns, type: :binary_id, on_delete: :delete_all),
        null: false

      add :email_template_id,
          references(:email_templates, type: :binary_id, on_delete: :nilify_all)

      # 邮件信息
      add :to_email, :string, null: false
      add :from_email, :string, null: false
      add :from_name, :string
      add :subject, :string, null: false
      add :html_content, :text
      add :text_content, :text

      # 发送状态
      # "sent", "failed", "pending"
      add :status, :string, null: false
      add :error_message, :text
      add :sent_at, :utc_datetime
      add :delivered_at, :utc_datetime

      # 元数据
      add :metadata, :map

      timestamps(type: :utc_datetime)
    end

    create index(:email_logs, [:campaign_id])
    create index(:email_logs, [:winning_record_id])
    create index(:email_logs, [:email_template_id])
    create index(:email_logs, [:to_email])
    create index(:email_logs, [:status])
    create index(:email_logs, [:sent_at])
    create index(:email_logs, [:campaign_id, :sent_at])
  end
end
