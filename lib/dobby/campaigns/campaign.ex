defmodule Dobby.Campaigns.Campaign do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "campaigns" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "draft"
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :background_image_url, :string
    field :theme_color, :string
    field :no_prize_message, :string
    field :rules_text, :string
    field :enable_protection, :boolean, default: false
    field :protection_count, :integer, default: 0

    belongs_to :admin, Dobby.Accounts.Admin
    has_many :prizes, Dobby.Campaigns.Prize
    has_many :transaction_numbers, Dobby.Lottery.TransactionNumber
    has_many :winning_records, Dobby.Lottery.WinningRecord
    has_many :campaign_email_templates, Dobby.Emails.CampaignEmailTemplate

    many_to_many :email_templates, Dobby.Emails.EmailTemplate,
      join_through: "campaign_email_templates",
      join_keys: [campaign_id: :id, email_template_id: :id]

    has_one :statistics, Dobby.Statistics.CampaignStatistic

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [
      :name,
      :description,
      :status,
      :starts_at,
      :ends_at,
      :background_image_url,
      :theme_color,
      :no_prize_message,
      :rules_text,
      :enable_protection,
      :protection_count,
      :admin_id
    ])
    |> validate_required([:name, :starts_at, :ends_at, :admin_id],
      message: "此欄位為必填"
    )
    |> validate_length(:name, min: 1, max: 200, message: "活動名稱長度應在 1-200 字元之間")
    |> validate_length(:description, max: 2000, message: "描述長度不能超過 2000 字元")
    |> validate_length(:no_prize_message, max: 100, message: "未中獎訊息長度不能超過 100 字元")
    |> validate_length(:rules_text, max: 5000, message: "規則文字長度不能超過 5000 字元")
    |> validate_inclusion(:status, ["draft", "active", "ended", "disabled"],
      message: "狀態必須為：草稿、進行中、已結束或已停用"
    )
    |> validate_number(:protection_count,
      greater_than_or_equal_to: 0,
      message: "保護數量必須大於或等於 0"
    )
    |> validate_date_range()
  end

  defp validate_date_range(changeset) do
    starts_at = get_change(changeset, :starts_at)
    ends_at = get_change(changeset, :ends_at)

    cond do
      starts_at && ends_at && DateTime.compare(starts_at, ends_at) != :lt ->
        add_error(changeset, :ends_at, "結束時間必須晚於開始時間")

      starts_at && DateTime.compare(starts_at, DateTime.utc_now()) == :lt &&
          Ecto.Changeset.get_field(changeset, :starts_at) != starts_at ->
        add_error(changeset, :starts_at, "開始時間不能早於現在")

      true ->
        changeset
    end
  end
end
