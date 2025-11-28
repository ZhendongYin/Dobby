defmodule Dobby.Lottery.TransactionNumber do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "transaction_numbers" do
    field :transaction_number, :string
    field :is_used, :boolean, default: false
    field :is_scratched, :boolean, default: false
    field :used_at, :utc_datetime
    field :ip_address, :string
    field :user_agent, :string

    belongs_to :campaign, Dobby.Campaigns.Campaign
    has_one :winning_record, Dobby.Lottery.WinningRecord

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(transaction_number, attrs) do
    transaction_number
    |> cast(attrs, [
      :transaction_number,
      :is_used,
      :is_scratched,
      :used_at,
      :ip_address,
      :user_agent,
      :campaign_id
    ])
    |> validate_required([:transaction_number, :campaign_id])
    |> unique_constraint(:transaction_number)
  end
end
