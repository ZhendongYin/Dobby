defmodule Dobby.Campaigns.Prize do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "prizes" do
    field :name, :string
    field :description, :string
    field :image_url, :string
    field :prize_type, :string
    field :total_quantity, :integer
    field :remaining_quantity, :integer
    field :daily_limit, :integer
    field :daily_used, :integer, default: 0
    field :probability_mode, :string, default: "percentage"
    field :probability, :decimal
    field :weight, :integer
    field :is_protected, :boolean, default: false
    field :redemption_guide, :string
    field :display_order, :integer, default: 0
    field :prize_code, :string

    belongs_to :campaign, Dobby.Campaigns.Campaign
    belongs_to :source_template, Dobby.PrizeLibrary.PrizeTemplate
    belongs_to :email_template, Dobby.Emails.EmailTemplate
    has_many :winning_records, Dobby.Lottery.WinningRecord

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(prize, attrs) do
    # 预处理：确保 total_quantity 和 remaining_quantity 不为 nil
    # 空字符串、nil 或 0 都转换为 0（因为数据库要求非空）
    attrs =
      attrs
      |> normalize_quantity_value("total_quantity")
      |> normalize_quantity_value("remaining_quantity")

    # 检查是否使用模板
    template_id = prize.source_template_id || Map.get(attrs, "source_template_id")
    template = if template_id, do: get_template_for_changeset(template_id), else: nil

    # 如果使用模板，从模板获取字段值以满足数据库约束
    # 虽然这些字段在 UI 中不可编辑，但数据库需要它们
    attrs =
      if template do
        # 移除用户提交的模板字段（防止被修改），然后从模板设置
        attrs
        |> Map.drop(["name", "description", "image_url", "prize_type", "redemption_guide"])
        |> Map.put("name", template.name)
        |> Map.put("description", template.description)
        |> Map.put("image_url", template.image_url)
        |> Map.put("prize_type", template.prize_type)
        |> Map.put("redemption_guide", template.redemption_guide)
      else
        attrs
      end

    changeset =
      prize
      |> cast(attrs, [
        :name,
        :description,
        :image_url,
        :prize_type,
        :total_quantity,
        :remaining_quantity,
        :daily_limit,
        :daily_used,
        :probability_mode,
        :probability,
        :weight,
        :is_protected,
        :redemption_guide,
        :display_order,
        :prize_code,
        :campaign_id,
        :source_template_id,
        :email_template_id
      ])
      |> validate_inclusion(:prize_type, ["physical", "virtual", "no_prize"])
      |> validate_inclusion(:probability_mode, ["percentage", "quantity_based"])
      |> validate_probability_required()
      |> validate_probability()
      |> validate_quantity()
      |> validate_prize_code()

    # 验证：如果没有 source_template_id，name 和 prize_type 是必需的
    if !changeset.changes[:source_template_id] && !prize.source_template_id do
      changeset
      |> validate_required([:name, :prize_type, :campaign_id])
    else
      # 如果有 source_template_id，只需要 campaign_id
      validate_required(changeset, [:campaign_id])
    end
  end

  # 辅助函数：获取模板用于 changeset（避免循环依赖）
  defp get_template_for_changeset(template_id) do
    alias Dobby.PrizeLibrary
    PrizeLibrary.get_template!(template_id)
  rescue
    _ -> nil
  end

  # 辅助函数：获取字段值，优先从模板读取
  def get_name(%{source_template: %{name: name}}) when not is_nil(name), do: name
  def get_name(%{name: name}) when not is_nil(name), do: name
  def get_name(_), do: nil

  def get_description(%{source_template: %{description: desc}}) when not is_nil(desc), do: desc
  def get_description(%{description: desc}) when not is_nil(desc), do: desc
  def get_description(_), do: nil

  def get_image_url(%{source_template: %{image_url: url}}) when not is_nil(url), do: url
  def get_image_url(%{image_url: url}) when not is_nil(url), do: url
  def get_image_url(_), do: nil

  def get_prize_type(%{source_template: %{prize_type: type}}) when not is_nil(type), do: type
  def get_prize_type(%{prize_type: type}) when not is_nil(type), do: type
  def get_prize_type(_), do: nil

  def get_redemption_guide(%{source_template: %{redemption_guide: guide}}) when not is_nil(guide),
    do: guide

  def get_redemption_guide(%{redemption_guide: guide}) when not is_nil(guide), do: guide
  def get_redemption_guide(_), do: nil

  # 规范化数量字段：空字符串或 nil 表示不限量（nil），其余转换为整数
  defp normalize_quantity_value(attrs, key) when is_binary(key) do
    if Map.has_key?(attrs, key) do
      value = Map.get(attrs, key)

      normalized_value =
        cond do
          value == "" || is_nil(value) ->
            nil

          is_binary(value) ->
            case Integer.parse(value) do
              {num, _} -> num
              :error -> nil
            end

          is_integer(value) ->
            value

          true ->
            nil
        end

      Map.put(attrs, key, normalized_value)
    else
      attrs
    end
  end

  defp validate_probability(changeset) do
    mode = get_field(changeset, :probability_mode)
    probability = get_change(changeset, :probability)

    cond do
      mode == "percentage" && probability ->
        if Decimal.compare(probability, Decimal.new(0)) == :lt ||
             Decimal.compare(probability, Decimal.new(100)) == :gt do
          add_error(changeset, :probability, "must be between 0 and 100")
        else
          changeset
        end

      true ->
        changeset
    end
  end

  defp validate_probability_required(changeset) do
    mode = get_change(changeset, :probability_mode) || get_field(changeset, :probability_mode)

    if mode == "percentage" do
      validate_required(changeset, [:probability])
    else
      changeset
    end
  end

  defp validate_quantity(changeset) do
    total = get_change(changeset, :total_quantity) || get_field(changeset, :total_quantity)

    remaining =
      get_change(changeset, :remaining_quantity) || get_field(changeset, :remaining_quantity)

    # 只有当 total 和 remaining 都不为 nil 且 > 0 时，才检查 remaining 是否超过 total
    # nil 或 0 表示不限量，不需要验证
    if total && total > 0 && remaining && remaining > 0 && remaining > total do
      add_error(changeset, :remaining_quantity, "cannot exceed total_quantity")
    else
      changeset
    end
  end

  defp validate_prize_code(changeset) do
    prize_type = get_change(changeset, :prize_type) || get_field(changeset, :prize_type)

    if prize_type == "virtual" do
      validate_required(changeset, [:prize_code])
    else
      changeset
    end
  end
end
