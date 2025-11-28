defmodule Dobby.Lottery do
  @moduledoc """
  The Lottery context.
  """

  import Ecto.Query, warn: false
  alias Dobby.Repo
  alias Dobby.Lottery.TransactionNumber
  alias Dobby.Lottery.WinningRecord
  alias Dobby.Context.Helpers

  # TransactionNumber functions

  @doc """
  Gets a transaction number by transaction_number string.
  """
  def get_transaction_number_by_code(transaction_number) when is_binary(transaction_number) do
    Repo.get_by(TransactionNumber, transaction_number: transaction_number)
  end

  @doc """
  Gets a single transaction_number.
  """
  def get_transaction_number!(id), do: Repo.get!(TransactionNumber, id)

  @doc """
  Creates a transaction_number.
  """
  def create_transaction_number(attrs \\ %{}) do
    %TransactionNumber{}
    |> TransactionNumber.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a transaction_number.
  """
  def update_transaction_number(%TransactionNumber{} = transaction_number, attrs) do
    transaction_number
    |> TransactionNumber.changeset(attrs)
    |> Repo.update()
  end

  # WinningRecord functions

  @doc """
  Gets a single winning_record.
  """
  def get_winning_record!(id), do: Repo.get!(WinningRecord, id)

  @doc """
  Gets a winning_record by transaction_number_id.
  """
  def get_winning_record_by_transaction_number(transaction_number_id) do
    Repo.get_by(WinningRecord, transaction_number_id: transaction_number_id)
  end

  @doc """
  Creates a winning_record.
  """
  def create_winning_record(attrs \\ %{}) do
    %WinningRecord{}
    |> WinningRecord.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a winning_record.
  """
  def update_winning_record(%WinningRecord{} = winning_record, attrs) do
    winning_record
    |> WinningRecord.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking winning_record changes.
  """
  def change_winning_record(%WinningRecord{} = winning_record, attrs \\ %{}) do
    WinningRecord.changeset(winning_record, attrs)
  end

  def list_winning_records(campaign_id, opts \\ %{}) do
    page = Helpers.fetch_integer_opt(opts, :page) || 1
    page_size = Helpers.fetch_integer_opt(opts, :page_size) || 20
    offset = (page - 1) * page_size
    sort_by = Helpers.fetch_opt(opts, :sort_by) || "inserted_at"
    sort_order = Helpers.fetch_opt(opts, :sort_order) || "desc"

    # If sorting by prize_name, we need to join prize first
    base_query =
      WinningRecord
      |> where([wr], wr.campaign_id == ^campaign_id)
      |> maybe_filter_status(Helpers.fetch_opt(opts, :status))
      |> maybe_search(Helpers.fetch_opt(opts, :search))

    # Join prize if needed for sorting
    query_with_join =
      if sort_by == "prize_name" do
        base_query
        |> join(:left, [wr], p in assoc(wr, :prize), as: :prize)
      else
        base_query
      end

    query = apply_winning_record_sort(query_with_join, sort_by, sort_order)

    total = Repo.aggregate(base_query, :count, :id)

    items =
      query
      |> preload([:transaction_number])
      |> preload(prize: :source_template)
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    %{
      items: items,
      total: total,
      page: page,
      page_size: page_size,
      total_pages: if(page_size > 0, do: ceil(total / page_size), else: 1)
    }
  end

  def count_winning_records(campaign_id, opts \\ %{}) do
    WinningRecord
    |> where([wr], wr.campaign_id == ^campaign_id)
    |> maybe_filter_status(Helpers.fetch_opt(opts, :status))
    |> maybe_search(Helpers.fetch_opt(opts, :search))
    |> select([wr], count(wr.id))
    |> Repo.one()
  end

  def winning_record_summary(campaign_id) do
    results =
      WinningRecord
      |> where([wr], wr.campaign_id == ^campaign_id)
      |> group_by([wr], wr.status)
      |> select([wr], {wr.status, count(wr.id)})
      |> Repo.all()

    total = Enum.reduce(results, 0, fn {_status, count}, acc -> acc + count end)

    # Calculate last 24 hours count
    last24h_time = DateTime.add(DateTime.utc_now(), -1, :day)

    last24h =
      WinningRecord
      |> where([wr], wr.campaign_id == ^campaign_id)
      |> where([wr], wr.inserted_at >= ^last24h_time)
      |> select([wr], count(wr.id))
      |> Repo.one()

    summary =
      Enum.reduce(results, %{"total" => total}, fn {status, count}, acc ->
        Map.put(acc, status || "unknown", count)
      end)
      |> Map.put_new("pending_submit", 0)
      |> Map.put_new("pending_process", 0)
      |> Map.put_new("fulfilled", 0)
      |> Map.put_new("expired", 0)
      |> Map.put_new("total", total)
      |> Map.put("last24h", last24h || 0)

    # Calculate pending_process percentage
    pending_process_count = Map.get(summary, "pending_process", 0)

    pending_process_pct =
      if total > 0 do
        Float.round(pending_process_count / total * 100, 1)
      else
        0.0
      end

    summary
    |> Map.put("pending_process_pct", pending_process_pct)
  end

  @doc """
  Batch fetch winning record summaries for multiple campaigns efficiently.
  Returns a map of campaign_id => summary.
  """
  def batch_winning_record_summaries(campaign_ids, last24h_time \\ nil)
      when is_list(campaign_ids) do
    if campaign_ids == [] do
      %{}
    else
      last24h_time = last24h_time || DateTime.add(DateTime.utc_now(), -1, :day)

      # Batch fetch status counts for all campaigns
      status_counts =
        WinningRecord
        |> where([wr], wr.campaign_id in ^campaign_ids)
        |> group_by([wr], [wr.campaign_id, wr.status])
        |> select([wr], {wr.campaign_id, wr.status, count(wr.id)})
        |> Repo.all()

      # Batch fetch last 24h counts
      last24h_counts =
        WinningRecord
        |> where([wr], wr.campaign_id in ^campaign_ids)
        |> where([wr], wr.inserted_at >= ^last24h_time)
        |> group_by([wr], wr.campaign_id)
        |> select([wr], {wr.campaign_id, count(wr.id)})
        |> Repo.all()
        |> Map.new()

      # Build summaries map
      summaries_map =
        Enum.reduce(status_counts, %{}, fn {campaign_id, status, count}, acc ->
          summary = Map.get(acc, campaign_id, %{"total" => 0})
          total = summary["total"] + count

          summary
          |> Map.put(status || "unknown", count)
          |> Map.put("total", total)
          |> then(&Map.put(acc, campaign_id, &1))
        end)

      # Add missing campaigns with empty summaries and last24h counts
      Enum.reduce(campaign_ids, summaries_map, fn campaign_id, acc ->
        summary =
          Map.get(acc, campaign_id, %{})
          |> Map.put_new("pending_submit", 0)
          |> Map.put_new("pending_process", 0)
          |> Map.put_new("fulfilled", 0)
          |> Map.put_new("expired", 0)
          |> Map.put_new("total", 0)
          |> Map.put("last24h", Map.get(last24h_counts, campaign_id, 0))

        # Calculate pending_process percentage
        total = summary["total"]
        pending_process_count = Map.get(summary, "pending_process", 0)

        pending_process_pct =
          if total > 0 do
            Float.round(pending_process_count / total * 100, 1)
          else
            0.0
          end

        Map.put(acc, campaign_id, Map.put(summary, "pending_process_pct", pending_process_pct))
      end)
    end
  end

  def get_winning_record_with_details!(id) do
    WinningRecord
    |> Repo.get!(id)
    |> Repo.preload([:campaign, :transaction_number])
    |> Repo.preload(prize: :source_template)
  end

  def update_winning_record_status(%WinningRecord{} = record, status) do
    record
    |> WinningRecord.changeset(%{"status" => status})
    |> Repo.update()
  end

  @doc """
  为虚拟奖品分配兑换码（单个通用码）。
  所有中奖用户都收到同一个码。
  """
  def assign_prize_code(%WinningRecord{} = winning_record, prize) do
    if prize.prize_type == "virtual" && prize.prize_code do
      # 直接使用奖品的通用码
      update_winning_record(winning_record, %{"virtual_code" => prize.prize_code})
    else
      {:ok, winning_record}
    end
  end

  # Lottery drawing functions

  alias Dobby.Lottery.ProbabilityEngine
  alias Dobby.Campaigns
  alias Dobby.Campaigns.Prize
  alias Dobby.Lottery.TransactionVerifier

  @doc """
  执行判奖并创建记录（事务处理）

  参数:
  - transaction_number: 交易码字符串
  - campaign_id: 活动 ID
  - ip_address: IP 地址
  - user_agent: 用户代理

  返回: {:ok, %{transaction_number: ..., winning_record: ..., prize: ...}} 或 {:error, reason}
  """
  def draw_and_record(transaction_number, campaign_id, ip_address, user_agent) do
    case Repo.transaction(fn ->
           # 1. 获取活动配置
           campaign = Campaigns.get_campaign!(campaign_id)

           # 2. 调用外部服务验证交易码
           case TransactionVerifier.verify(transaction_number, campaign) do
             {:ok, _meta} ->
               :ok

             {:error, reason} ->
               Repo.rollback({:transaction_verification_failed, reason})
           end

           # 3. 查找或创建交易记录
           tx_number =
             case ensure_transaction_record(transaction_number, campaign.id) do
               {:ok, tx} ->
                 tx

               {:error, :campaign_mismatch} ->
                 Repo.rollback(:transaction_campaign_mismatch)

               {:error, changeset} ->
                 Repo.rollback({:transaction_persist_error, changeset})
             end

           # 4. 检查是否已使用
           if tx_number.is_used do
             Repo.rollback(:transaction_already_used)
           end

           # 5. 检查活动状态
           unless campaign.status == "active" do
             Repo.rollback(:campaign_inactive)
           end

           # 检查活动时间
           now = DateTime.utc_now()

           cond do
             campaign.starts_at && DateTime.compare(now, campaign.starts_at) == :lt ->
               Repo.rollback(:campaign_not_started)

             campaign.ends_at && DateTime.compare(now, campaign.ends_at) == :gt ->
               Repo.rollback(:campaign_ended)

             true ->
               :ok
           end

           # 6. 获取当前活动抽奖次数（用于大奖保护）
           draw_count = get_draw_count(campaign.id)

           # 7. 执行判奖（传入抽奖次数）
           case ProbabilityEngine.draw_prize(campaign.id, draw_count) do
             {:ok, :no_prize} ->
               # 创建无奖品记录
               create_no_prize_record(tx_number, campaign, ip_address, user_agent)

             {:ok, prize} ->
               # 8. 扣减库存
               case decrement_prize_quantity(prize) do
                 :ok ->
                   # 9. 更新每日使用量（如果有每日限制）
                   case update_daily_usage(prize) do
                     :ok ->
                       # 10. 标记交易码为已使用
                       mark_transaction_used(tx_number, ip_address, user_agent)

                       # 11. 创建中奖记录
                       winning_record =
                         create_winning_record_for_prize(tx_number, prize, campaign)

                       %{
                         transaction_number: tx_number,
                         winning_record: winning_record,
                         prize: prize
                       }

                     {:error, :daily_limit_exceeded} ->
                       # 每日上限已满，改为无奖品
                       create_no_prize_record(tx_number, campaign, ip_address, user_agent)
                   end

                 {:error, :insufficient_stock} ->
                   # 库存不足，改为无奖品
                   create_no_prize_record(tx_number, campaign, ip_address, user_agent)
               end
           end
         end) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_draw_count(campaign_id) do
    from(t in TransactionNumber,
      where: t.campaign_id == ^campaign_id and t.is_used == true,
      select: count(t.id)
    )
    |> Repo.one()
  end

  defp create_no_prize_record(tx_number, campaign, ip_address, user_agent) do
    # 创建无奖品记录
    no_prize = get_no_prize(campaign.id)

    # 标记交易码为已使用
    mark_transaction_used(tx_number, ip_address, user_agent)

    # 创建中奖记录（无奖品）- 直接标记为已完成，因为不需要用户提交信息
    winning_record =
      create_winning_record(%{
        "transaction_number_id" => tx_number.id,
        "prize_id" => no_prize.id,
        "campaign_id" => campaign.id,
        # 改为 fulfilled
        "status" => "fulfilled"
      })
      |> case do
        {:ok, record} ->
          record

        {:error, changeset} ->
          raise "Failed to create winning record: #{inspect(changeset.errors)}"
      end

    %{
      transaction_number: tx_number,
      winning_record: winning_record,
      prize: no_prize
    }
  end

  defp get_no_prize(campaign_id) do
    case Repo.one(
           from(p in Prize,
             where: p.campaign_id == ^campaign_id and p.prize_type == "no_prize",
             limit: 1
           )
         ) do
      nil -> raise "No prize record not found for campaign"
      prize -> prize
    end
  end

  defp decrement_prize_quantity(prize) do
    # 如果 total_quantity 为 nil 或 0，视为不限量，不扣减库存
    if prize.total_quantity && prize.total_quantity > 0 do
      result =
        from(p in Prize,
          where:
            p.id == ^prize.id and
              is_nil(p.remaining_quantity) == false and
              p.remaining_quantity > 0,
          update: [set: [remaining_quantity: p.remaining_quantity - 1]]
        )
        |> Repo.update_all([])

      case result do
        {1, _} -> :ok
        {0, _} -> {:error, :insufficient_stock}
      end
    else
      :ok
    end
  end

  defp update_daily_usage(prize) do
    if prize.daily_limit && prize.daily_limit > 0 do
      {count, _} =
        from(p in Prize,
          where:
            p.id == ^prize.id and
              (is_nil(p.daily_used) or p.daily_used < p.daily_limit),
          update: [set: [daily_used: p.daily_used + 1]]
        )
        |> Repo.update_all([])

      if count == 1 do
        :ok
      else
        {:error, :daily_limit_exceeded}
      end
    else
      :ok
    end
  end

  defp mark_transaction_used(tx_number, ip_address, user_agent) do
    from(t in TransactionNumber,
      where: t.id == ^tx_number.id,
      update: [
        set: [
          is_used: true,
          used_at: ^DateTime.utc_now(),
          ip_address: ^ip_address,
          user_agent: ^user_agent
        ]
      ]
    )
    |> Repo.update_all([])
  end

  defp create_winning_record_for_prize(tx_number, prize, campaign) do
    create_winning_record(%{
      "transaction_number_id" => tx_number.id,
      "prize_id" => prize.id,
      "campaign_id" => campaign.id,
      "status" => "pending_submit"
    })
    |> case do
      {:ok, record} -> record
      {:error, changeset} -> raise "Failed to create winning record: #{inspect(changeset.errors)}"
    end
  end

  defp ensure_transaction_record(transaction_number, campaign_id) do
    case get_transaction_number_by_code(transaction_number) do
      nil ->
        %TransactionNumber{}
        |> TransactionNumber.changeset(%{
          "transaction_number" => transaction_number,
          "campaign_id" => campaign_id
        })
        |> Repo.insert()

      %TransactionNumber{campaign_id: ^campaign_id} = tx ->
        {:ok, tx}

      %TransactionNumber{} ->
        {:error, :campaign_mismatch}
    end
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, "" = _), do: query
  defp maybe_filter_status(query, "all"), do: query

  defp maybe_filter_status(query, status) do
    where(query, [wr], wr.status == ^status)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, "" = _), do: query

  defp maybe_search(query, term) do
    escaped = Helpers.escape_like(term)
    like = "%#{escaped}%"

    from wr in query,
      left_join: tn in assoc(wr, :transaction_number),
      where:
        ilike(wr.email, ^like) or
          ilike(wr.name, ^like) or
          ilike(tn.transaction_number, ^like)
  end

  defp apply_winning_record_sort(query, field, order) do
    direction = if order == "desc", do: :desc, else: :asc

    case field do
      "name" -> order_by(query, [wr], [{^direction, wr.name}])
      "email" -> order_by(query, [wr], [{^direction, wr.email}])
      "status" -> order_by(query, [wr], [{^direction, wr.status}])
      "prize_name" ->
        # Query already has prize joined in list_winning_records when sort_by is prize_name
        order_by(query, [wr, p], [{^direction, p.name}])
      "inserted_at" -> order_by(query, [wr], [{^direction, wr.inserted_at}])
      # default
      _ -> order_by(query, [wr], [{^direction, wr.inserted_at}])
    end
  end
end
