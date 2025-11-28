defmodule Dobby.Campaigns.ActivityLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "campaign_activity_logs" do
    field :action, :string
    field :target_type, :string
    field :target_id, :binary_id
    field :field, :string
    field :from_value, :string
    field :to_value, :string
    field :metadata, :map

    belongs_to :campaign, Dobby.Campaigns.Campaign
    belongs_to :admin, Dobby.Accounts.Admin

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(activity_log, attrs) do
    activity_log
    |> cast(attrs, [
      :campaign_id,
      :admin_id,
      :action,
      :target_type,
      :target_id,
      :field,
      :from_value,
      :to_value,
      :metadata
    ])
    |> validate_required([:campaign_id, :action, :target_type])
    |> validate_inclusion(:action, [
      "update_campaign",
      "create_prize",
      "update_prize",
      "delete_prize"
    ])
    |> validate_inclusion(:target_type, ["campaign", "prize"])
  end
end
