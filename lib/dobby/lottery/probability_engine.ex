defmodule Dobby.Lottery.ProbabilityEngine do
  @moduledoc """
  概率计算引擎

  支持两种模式：
  1. 百分比模式 (percentage): 使用 probability 字段，0.00-100.00
  2. 数量模式 (quantity_based): 使用 weight 字段，按剩余数量随机

  大奖保护：
  - 如果活动启用保护，前 N 次抽奖会排除受保护的奖品
  """

  import Ecto.Query
  alias Dobby.Repo
  alias Dobby.Campaigns.Campaign
  alias Dobby.Campaigns.Prize

  @doc """
  执行判奖

  参数:
  - campaign_id: 活动 ID
  - draw_count: 当前抽奖次数（用于大奖保护）

  返回: {:ok, prize} 或 {:ok, :no_prize}
  """
  def draw_prize(campaign_id, draw_count \\ 0) do
    # 1. 获取活动配置
    campaign = Repo.get!(Campaign, campaign_id)

    # 2. 获取所有奖品并过滤可用性（库存、每日上限）
    # 在数据库层进行过滤以提高性能
    prizes =
      from(p in Prize,
        where: p.campaign_id == ^campaign_id,
        # 库存可用：total_quantity为nil（不限量）或(total_quantity > 0且remaining_quantity > 0)
        where:
          is_nil(p.total_quantity) or
            (p.total_quantity > 0 and not is_nil(p.remaining_quantity) and
               p.remaining_quantity > 0),
        # 每日限额可用：daily_limit为nil、daily_limit <= 0（不限量）或daily_used < daily_limit
        where:
          is_nil(p.daily_limit) or
            p.daily_limit <= 0 or
            (p.daily_limit > 0 and (is_nil(p.daily_used) or p.daily_used < p.daily_limit))
      )
      |> Repo.all()

    # 3. 如果启用保护且 draw_count < protection_count，排除受保护奖品
    prizes =
      if campaign.enable_protection && draw_count < campaign.protection_count do
        Enum.reject(prizes, & &1.is_protected)
      else
        prizes
      end

    # 4. 如果没有有效奖品，返回无奖品
    if prizes == [] do
      {:ok, :no_prize}
    else
      # 5. 根据概率模式计算
      result = calculate_prize(prizes)

      # 6. 返回结果
      case result do
        nil -> {:ok, :no_prize}
        prize -> {:ok, prize}
      end
    end
  end

  defp calculate_prize(prizes) do
    # 分离不同模式的奖品
    {percentage_prizes, quantity_prizes} =
      Enum.split_with(prizes, &(&1.probability_mode == "percentage"))

    # 计算百分比模式的总概率
    total_percentage =
      Enum.reduce(percentage_prizes, Decimal.new("0"), fn prize, acc ->
        if prize.probability do
          Decimal.add(acc, prize.probability)
        else
          acc
        end
      end)

    # 计算数量模式的总权重
    total_weight =
      Enum.reduce(quantity_prizes, 0, fn prize, acc ->
        weight = prize.weight || prize.remaining_quantity || 0
        acc + weight
      end)

    # 生成随机数 (0-100) - 使用 (uniform(10001) - 1) / 100.0 确保精确的 [0.0, 100.0] 范围
    random = (:rand.uniform(10001) - 1) / 100.0

    # 先判断百分比模式
    if Decimal.compare(total_percentage, Decimal.new("0")) == :gt do
      case select_by_percentage(percentage_prizes, total_percentage, random) do
        nil -> select_by_quantity(quantity_prizes, total_weight)
        prize -> prize
      end
    else
      # 只有数量模式
      select_by_quantity(quantity_prizes, total_weight)
    end
  end

  defp select_by_percentage(prizes, total_percentage, random) do
    # 如果随机数在总概率范围内，选择奖品
    total_float = Decimal.to_float(total_percentage)

    if random <= total_float do
      # 累积概率选择
      select_prize_by_cumulative(prizes, random, Decimal.new(0))
    else
      nil
    end
  end

  defp select_prize_by_cumulative([], _random, _cumulative), do: nil

  defp select_prize_by_cumulative([prize | rest], random, cumulative) do
    probability = prize.probability || Decimal.new(0)
    new_cumulative = Decimal.add(cumulative, probability)
    cumulative_float = Decimal.to_float(cumulative)
    new_cumulative_float = Decimal.to_float(new_cumulative)

    if random >= cumulative_float && random <= new_cumulative_float do
      prize
    else
      select_prize_by_cumulative(rest, random, new_cumulative)
    end
  end

  defp select_by_quantity(prizes, total_weight) when total_weight > 0 do
    # 生成随机数 (1-total_weight)
    random = :rand.uniform(total_weight)

    # 累积权重选择
    select_prize_by_weight(prizes, random, 0)
  end

  defp select_by_quantity(_prizes, _total_weight), do: nil

  defp select_prize_by_weight([], _random, _cumulative), do: nil

  defp select_prize_by_weight([prize | rest], random, cumulative) do
    weight = prize.weight || prize.remaining_quantity || 0
    new_cumulative = cumulative + weight

    if random > cumulative && random <= new_cumulative do
      prize
    else
      select_prize_by_weight(rest, random, new_cumulative)
    end
  end
end
