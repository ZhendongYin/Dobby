defmodule Dobby.Emails.EmailLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "email_logs" do
    field :to_email, :string
    field :from_email, :string
    field :from_name, :string
    field :subject, :string
    field :html_content, :string
    field :text_content, :string
    field :status, :string
    field :error_message, :string
    field :sent_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :metadata, :map

    belongs_to :winning_record, Dobby.Lottery.WinningRecord
    belongs_to :campaign, Dobby.Campaigns.Campaign
    belongs_to :email_template, Dobby.Emails.EmailTemplate

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(email_log, attrs) do
    email_log
    |> cast(attrs, [
      :winning_record_id,
      :campaign_id,
      :email_template_id,
      :to_email,
      :from_email,
      :from_name,
      :subject,
      :html_content,
      :text_content,
      :status,
      :error_message,
      :sent_at,
      :delivered_at,
      :metadata
    ])
    |> validate_required([:campaign_id, :to_email, :from_email, :subject, :status])
    |> validate_inclusion(:status, ["sent", "failed", "pending"])
    |> validate_format(:to_email, ~r/^[^\s]+@[^\s]+$/)
  end
end
