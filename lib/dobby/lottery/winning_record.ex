defmodule Dobby.Lottery.WinningRecord do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "winning_records" do
    field :email, :string
    field :name, :string
    field :phone, :string
    field :address, :string
    field :virtual_code, :string
    field :status, :string, default: "pending_submit"
    field :email_sent, :boolean, default: false
    field :email_sent_at, :utc_datetime
    field :fulfilled_at, :utc_datetime

    belongs_to :transaction_number, Dobby.Lottery.TransactionNumber
    belongs_to :prize, Dobby.Campaigns.Prize
    belongs_to :campaign, Dobby.Campaigns.Campaign

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(winning_record, attrs) do
    winning_record
    |> cast(attrs, [
      :email,
      :name,
      :phone,
      :address,
      :virtual_code,
      :status,
      :email_sent,
      :email_sent_at,
      :fulfilled_at,
      :transaction_number_id,
      :prize_id,
      :campaign_id
    ])
    |> validate_required([:transaction_number_id, :prize_id, :campaign_id])
    |> validate_inclusion(:status, [
      "pending_submit",
      "pending_process",
      "fulfilled",
      "expired"
    ])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:transaction_number_id)
  end
end
