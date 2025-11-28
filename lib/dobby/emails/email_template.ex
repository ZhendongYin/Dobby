defmodule Dobby.Emails.EmailTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "email_templates" do
    field :name, :string
    field :subject, :string
    field :html_content, :string
    field :text_content, :string
    field :variables, :map, default: %{}
    field :is_default, :boolean, virtual: true, default: false

    has_many :campaign_email_templates, Dobby.Emails.CampaignEmailTemplate

    many_to_many :campaigns, Dobby.Campaigns.Campaign,
      join_through: "campaign_email_templates",
      join_keys: [email_template_id: :id, campaign_id: :id]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(email_template, attrs) do
    email_template
    |> cast(attrs, [
      :name,
      :subject,
      :html_content,
      :text_content,
      :variables,
      :is_default
    ])
    |> validate_required([:name, :subject, :html_content])
  end
end
