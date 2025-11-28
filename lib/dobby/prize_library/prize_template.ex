defmodule Dobby.PrizeLibrary.PrizeTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "prize_templates" do
    field :name, :string
    field :prize_type, :string, default: "physical"
    field :image_url, :string
    field :description, :string
    field :redemption_guide, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :prize_type, :image_url, :description, :redemption_guide])
    |> validate_required([:name, :prize_type])
    |> validate_inclusion(:prize_type, ["physical", "virtual", "no_prize"])
  end
end
