defmodule Dobby.Emails.CampaignEmailTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "campaign_email_templates" do
    belongs_to :campaign, Dobby.Campaigns.Campaign
    belongs_to :email_template, Dobby.Emails.EmailTemplate
    field :is_default, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(campaign_email_template, attrs) do
    campaign_email_template
    |> cast(attrs, [:campaign_id, :email_template_id, :is_default])
    |> validate_required([:campaign_id, :email_template_id])
    |> unique_constraint([:campaign_id, :email_template_id],
      name: :campaign_email_templates_unique_pairs
    )
  end
end
