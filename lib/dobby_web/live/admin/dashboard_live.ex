defmodule DobbyWeb.Admin.DashboardLive do
  use DobbyWeb, :live_view

  alias Dobby.Campaigns
  alias Dobby.Lottery
  alias Dobby.Emails
  alias Dobby.Repo
  alias Dobby.Lottery.WinningRecord
  import Ecto.Query

  def mount(_params, _session, socket) do
    {:ok, load_dashboard_data(socket)}
  end

  defp load_dashboard_data(socket) do
    now = DateTime.utc_now()
    admin_id = socket.assigns.current_admin.id
    campaigns_result = Campaigns.list_campaigns(%{admin_id: admin_id, page: 1, page_size: 1000})
    campaigns = campaigns_result.items |> Repo.preload([:prizes])
    campaign_ids = Enum.map(campaigns, & &1.id)

    socket
    |> assign(:kpis, calculate_kpis_optimized(campaigns, campaign_ids, now))
    |> assign(:campaign_cards, get_spotlight_campaigns_optimized(campaigns, campaign_ids, now))
    |> assign(:live_feed, build_live_feed(now))
    |> assign(:tasks, build_tasks(campaigns, now))
    |> assign(:email_insights, get_email_insights(now))
    |> assign(:notifications, build_notifications(campaigns, now))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :admin, current_nav: :dashboard}}>
      <.page_container class="space-y-10 pb-12">
    <!-- KPIs -->
        <section>
          <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
            <.card
              :for={metric <- @kpis}
              class="p-5"
            >
              <p class="text-sm uppercase tracking-[0.3em] text-base-content/50">{metric.label}</p>
              <div class="mt-2 flex items-end justify-between">
                <p class="text-3xl font-semibold text-base-content">{metric.value}</p>
                <.badge variant={delta_badge_variant(metric.delta_color)}>
                  {metric.delta}
                </.badge>
              </div>
              <p class="mt-1 text-xs text-base-content/70">{metric.caption}</p>
            </.card>
          </div>
        </section>

    <!-- Campaign spotlight + Email -->
        <section class="grid gap-6 xl:grid-cols-[2fr,1fr]">
          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold text-base-content">Campaign Spotlight</h2>
              <.link
                navigate={~p"/admin/campaigns"}
                class="text-sm text-primary hover:text-primary/80"
              >
                查看全部
              </.link>
            </div>
            <div class="grid gap-4 md:grid-cols-2">
              <.card
                :for={campaign <- @campaign_cards}
                class="bg-base-100/85 border border-base-300 backdrop-blur p-5 flex flex-col gap-4 text-base-content"
              >
                <div class="flex items-center justify-between">
                  <p class="text-sm uppercase tracking-[0.3em] text-base-content/50">
                    {campaign.code}
                  </p>
                  <.badge variant={status_badge_variant(campaign.status_color)}>
                    {campaign.status}
                  </.badge>
                </div>
                <div>
                  <h3 class="text-xl font-semibold">{campaign.name}</h3>
                  <p class="text-sm text-base-content/70 mt-1">{campaign.subtitle}</p>
                </div>
                <div class="flex items-center justify-between text-sm text-base-content/70">
                  <div>
                    <p class="text-xs uppercase tracking-wide text-base-content/50">參與人次</p>
                    <p class="font-semibold text-base-content">{campaign.participants}</p>
                  </div>
                  <div>
                    <p class="text-xs uppercase tracking-wide text-base-content/50">兌換率</p>
                    <p class="font-semibold text-base-content">{campaign.conversion}</p>
                  </div>
                  <div>
                    <p class="text-xs uppercase tracking-wide text-base-content/50">剩餘獎品</p>
                    <p class="font-semibold text-base-content">{campaign.inventory}</p>
                  </div>
                </div>
                <div class="flex flex-wrap gap-2">
                  <.link
                    :for={cta <- campaign.cta}
                    navigate={cta.href}
                    class="inline-flex items-center gap-1 rounded-full border border-base-200 px-3 py-1 text-xs font-semibold text-base-content/80 hover:bg-base-200/60"
                  >
                    {cta.label}
                    <.icon name="hero-arrow-up-right" class="h-3.5 w-3.5" />
                  </.link>
                </div>
              </.card>
            </div>
          </div>

          <div class="rounded-3xl bg-slate-900 text-white p-6 shadow-2xl">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm uppercase tracking-[0.3em] text-white/50">Email Insights</p>
                <p class="text-2xl font-semibold mt-1">{@email_insights.total_sent} 封 / 24h</p>
              </div>
              <div class="rounded-2xl bg-white/10 px-3 py-2 text-xs uppercase tracking-[0.3em]">
                SES
              </div>
            </div>
            <div class="mt-6 space-y-4">
              <div class="flex items-center justify-between text-sm">
                <p>開信率</p>
                <p class="font-semibold">{@email_insights.open_rate}</p>
              </div>
              <div class="flex items-center justify-between text-sm">
                <p>成功發送</p>
                <p class="font-semibold">{@email_insights.success_rate}</p>
              </div>
              <div>
                <p class="text-xs uppercase tracking-[0.3em] text-white/50 mb-1">狀態</p>
                <div class="h-2 rounded-full bg-white/10 overflow-hidden">
                  <div
                    class="h-full bg-gradient-to-r from-emerald-400 to-lime-300"
                    style={"width: #{@email_insights.queue_fill}"}
                  />
                </div>
                <p class="text-xs text-white/70 mt-2">
                  佇列負載 <span class="font-semibold text-white">{@email_insights.queue_fill}</span>
                </p>
              </div>
            </div>
          </div>
        </section>

    <!-- Live feed + Tasks -->
        <section class="grid gap-6 lg:grid-cols-[2fr,1fr]">
          <.card>
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold text-base-content">Live Pulse</h2>
              <.badge variant="success">
                即時更新
              </.badge>
            </div>
            <div class="space-y-4">
              <.card
                :for={event <- @live_feed}
                class="px-4 py-3"
              >
                <div class={[
                  "mt-1 h-2.5 w-2.5 rounded-full",
                  event.dot_color
                ]} />
                <div class="flex-1">
                  <p class="text-sm font-semibold text-base-content">{event.title}</p>
                  <p class="text-sm text-base-content/70">{event.subtitle}</p>
                </div>
                <span class="text-xs text-base-content/50">{event.time_ago}</span>
              </.card>
            </div>
          </.card>

          <.card class="flex flex-col">
            <div class="flex items-center justify-between mb-4">
              <h2 class="text-lg font-semibold text-base-content">營運待辦</h2>
              <span class="text-xs text-base-content/50">
                {Enum.count(@tasks)} 項
              </span>
            </div>
            <div class="flex-1 space-y-3">
              <.card
                :for={task <- @tasks}
                class={
                  if(task.priority == :high,
                    do: "px-4 py-3 text-sm flex items-start gap-3 border-rose-200 bg-rose-50",
                    else: "px-4 py-3 text-sm flex items-start gap-3 border-slate-200 bg-white"
                  )
                }
              >
                <div class="mt-1">
                  <.badge
                    variant={task_priority_badge_variant(task.priority)}
                    class="text-[10px] px-2 py-0.5"
                  >
                    {task.badge}
                  </.badge>
                </div>
                <div class="flex-1">
                  <p class="font-semibold text-base-content">{task.title}</p>
                  <p class="text-xs text-base-content/70 mt-1">{task.description}</p>
                </div>
                <.link
                  navigate={task.href}
                  class="text-xs font-semibold text-primary hover:text-primary/80 transition-colors"
                >
                  前往
                </.link>
              </.card>
            </div>
          </.card>
        </section>

    <!-- Notifications -->
        <.card class="bg-base-200/50 border-base-300">
          <div class="flex items-center justify-between">
            <h2 class="text-lg font-semibold text-base-content">通知 / 警示</h2>
            <span class="text-xs text-base-content/60">自動監控</span>
          </div>
          <div class="mt-4 grid gap-4 md:grid-cols-2">
            <.card
              :for={note <- @notifications}
              class="p-5 flex flex-col gap-2"
            >
              <div class="flex items-center gap-2">
                <span class={[
                  "inline-flex h-2.5 w-2.5 rounded-full",
                  note.level_color
                ]} />
                <p class="text-sm font-semibold text-base-content">{note.title}</p>
              </div>
              <p class="text-sm text-base-content/70">{note.body}</p>
              <.link
                navigate={note.href}
                class="text-sm font-semibold text-primary hover:text-primary/80 transition-colors"
              >
                {note.action}
              </.link>
            </.card>
          </div>
        </.card>
      </.page_container>
    </Layouts.app>
    """
  end

  defp calculate_kpis_optimized(campaigns, campaign_ids, now) do
    active_campaigns = Enum.filter(campaigns, &(&1.status == "active"))
    active_count = length(active_campaigns)

    # 今日参与数（过去 24 小时）- 只统计当前管理员的活动
    last24h = DateTime.add(now, -1, :day)

    today_participants =
      if campaign_ids != [] do
        from(wr in WinningRecord,
          where: wr.inserted_at >= ^last24h and wr.campaign_id in ^campaign_ids
        )
        |> Repo.aggregate(:count, :id)
      else
        0
      end

    # 使用聚合查询获取统计数据，而不是加载所有记录
    stats =
      if campaign_ids != [] do
        # 总参与数
        total_participants =
          from(wr in WinningRecord, where: wr.campaign_id in ^campaign_ids)
          |> Repo.aggregate(:count, :id)

        # 中奖数（非no_prize且未过期）
        winners =
          from(wr in WinningRecord,
            join: p in assoc(wr, :prize),
            where:
              wr.campaign_id in ^campaign_ids and wr.status != "expired" and
                p.prize_type != "no_prize"
          )
          |> Repo.aggregate(:count, :id)

        # 待处理中奖
        pending =
          from(wr in WinningRecord,
            where:
              wr.campaign_id in ^campaign_ids and
                wr.status in ["pending_submit", "pending_process"]
          )
          |> Repo.aggregate(:count, :id)

        %{
          total_participants: total_participants,
          winners: winners,
          pending: pending
        }
      else
        %{total_participants: 0, winners: 0, pending: 0}
      end

    # 中奖率
    win_rate =
      if stats.total_participants > 0 do
        Float.round(stats.winners / stats.total_participants * 100, 1)
      else
        0.0
      end

    [
      %{
        label: "進行中活動",
        value: "#{active_count}",
        delta: "+#{active_count}",
        delta_color: "bg-emerald-50 text-emerald-700",
        caption: "共 #{length(campaigns)} 個活動"
      },
      %{
        label: "今日參與數",
        value: "#{format_number(today_participants)}",
        delta: "+#{today_participants}",
        delta_color: "bg-emerald-50 text-emerald-700",
        caption: "過去 24 小時"
      },
      %{
        label: "中獎率",
        value: "#{win_rate}%",
        delta: "#{if win_rate < 10, do: "-", else: "+"}#{win_rate}%",
        delta_color:
          if(win_rate < 10,
            do: "bg-amber-50 text-amber-700",
            else: "bg-emerald-50 text-emerald-700"
          ),
        caption: "#{stats.winners} / #{stats.total_participants} 筆"
      },
      %{
        label: "待處理中獎",
        value: "#{stats.pending}",
        delta: if(stats.pending > 0, do: "+#{stats.pending}", else: "0"),
        delta_color:
          if(stats.pending > 0,
            do: "bg-amber-50 text-amber-700",
            else: "bg-slate-50 text-slate-700"
          ),
        caption: "需人工處理"
      }
    ]
  end

  defp get_spotlight_campaigns_optimized(campaigns, _campaign_ids, now) do
    filtered_campaigns =
      campaigns
      |> Enum.filter(fn campaign ->
        campaign.status == "active" ||
          (campaign.status == "draft" && campaign.starts_at &&
             DateTime.compare(campaign.starts_at, now) == :gt)
      end)

    # Batch fetch summaries for all campaigns
    filtered_campaign_ids = Enum.map(filtered_campaigns, & &1.id)
    summaries_map = Lottery.batch_winning_record_summaries(filtered_campaign_ids)

    filtered_campaigns
    |> Enum.map(fn campaign ->
      summary = Map.get(summaries_map, campaign.id, %{"total" => 0, "fulfilled" => 0})
      participants = summary["total"] || 0
      fulfilled = summary["fulfilled"] || 0

      conversion =
        if participants > 0 do
          Float.round(fulfilled / participants * 100, 1)
        else
          0.0
        end

      inventory_pct = calculate_inventory_percentage(campaign)

      %{
        id: campaign.id,
        code: String.slice(campaign.id, 0, 8) |> String.upcase(),
        name: campaign.name,
        subtitle: campaign.description || "活動進行中",
        status: status_label(campaign.status),
        status_color: status_color(campaign.status),
        participants: format_number(participants),
        conversion: "#{conversion}%",
        inventory: "#{inventory_pct}%",
        cta: [
          %{label: "查看詳情", href: ~p"/admin/campaigns/#{campaign.id}/preview"}
        ],
        priority: calculate_priority(campaign, now)
      }
    end)
    |> Enum.sort_by(& &1.priority, :desc)
    |> Enum.take(4)
  end

  defp build_live_feed(now) do
    feed = []
    last_hour = DateTime.add(now, -1, :hour)

    # 最近的中奖记录（过去 1 小时）
    recent_winners =
      from(wr in WinningRecord,
        where: wr.inserted_at >= ^last_hour,
        order_by: [desc: wr.inserted_at],
        limit: 10,
        preload: [:prize, :campaign]
      )
      |> Repo.all()

    feed =
      Enum.map(recent_winners, fn record ->
        prize_name = if record.prize, do: record.prize.name, else: "未知獎品"
        campaign_name = if record.campaign, do: record.campaign.name, else: "未知活動"

        %{
          title: "新中獎記錄",
          subtitle: "#{prize_name} · #{campaign_name}",
          time_ago: format_time_ago(record.inserted_at, now),
          timestamp: record.inserted_at,
          dot_color: "bg-emerald-400"
        }
      end) ++ feed

    # 最近的邮件发送（过去 1 小时）
    recent_emails_result = Emails.list_all_email_logs(limit: 10)

    recent_emails =
      recent_emails_result.items
      |> Enum.filter(fn log ->
        log.inserted_at && DateTime.compare(log.inserted_at, last_hour) == :gt
      end)
      |> Enum.take(5)

    feed =
      Enum.map(recent_emails, fn log ->
        status_text = if log.status == "sent", do: "發送成功", else: "發送失敗"
        timestamp = log.sent_at || log.inserted_at

        %{
          title: "郵件#{status_text}",
          subtitle: "#{log.to_email} · #{String.slice(log.subject || "", 0, 30)}",
          time_ago: format_time_ago(timestamp, now),
          timestamp: timestamp,
          dot_color: if(log.status == "sent", do: "bg-indigo-400", else: "bg-rose-400")
        }
      end) ++ feed

    # 最近的活动日志（过去 1 小时）
    recent_logs =
      from(al in Dobby.Campaigns.ActivityLog,
        where: al.inserted_at >= ^last_hour,
        order_by: [desc: al.inserted_at],
        limit: 5,
        preload: [:campaign, :admin]
      )
      |> Repo.all()

    feed =
      Enum.map(recent_logs, fn log ->
        admin_name = if log.admin, do: log.admin.email, else: "系統"
        campaign_name = if log.campaign, do: log.campaign.name, else: "活動"

        %{
          title: "活動已更新",
          subtitle: "#{campaign_name} · #{admin_name}",
          time_ago: format_time_ago(log.inserted_at, now),
          timestamp: log.inserted_at,
          dot_color: "bg-indigo-400"
        }
      end) ++ feed

    # 按时间戳排序（最近的在前），直接使用 DateTime 而不是解析字符串
    feed
    |> Enum.sort_by(
      fn item ->
        # 使用 timestamp 字段进行排序，如果没有则使用当前时间作为默认值
        item[:timestamp] || now
      end,
      {:desc, DateTime}
    )
    |> Enum.take(10)
    |> Enum.map(fn item -> Map.delete(item, :timestamp) end)
  end

  defp build_tasks(campaigns, now) do
    tasks = []

    # 待提交信息的中奖者
    pending_submit_count =
      from(wr in WinningRecord,
        where: wr.status == "pending_submit"
      )
      |> Repo.aggregate(:count, :id)

    tasks =
      if pending_submit_count > 0 do
        [
          %{
            title: "#{pending_submit_count} 位得獎者待補收件資訊",
            description: "中獎者尚未提交完整資訊，系統已自動發送提醒。",
            priority: :high,
            badge: "P1",
            href: ~p"/admin/campaigns"
          }
          | tasks
        ]
      else
        tasks
      end

    # 待处理的中奖者
    pending_process_count =
      from(wr in WinningRecord,
        where: wr.status == "pending_process"
      )
      |> Repo.aggregate(:count, :id)

    tasks =
      if pending_process_count > 0 do
        [
          %{
            title: "#{pending_process_count} 筆中獎記錄待處理",
            description: "已收到完整資訊，等待人工確認與發放。",
            priority: :high,
            badge: "P1",
            href: ~p"/admin/campaigns"
          }
          | tasks
        ]
      else
        tasks
      end

    # 即将结束的活动
    ending_soon = Enum.filter(campaigns, &ending_soon?(&1, now))

    tasks =
      if length(ending_soon) > 0 do
        [
          %{
            title: "#{length(ending_soon)} 個活動即將結束",
            description: "請檢查獎品庫存與通知流程，確保活動完美收尾。",
            priority: :medium,
            badge: "P2",
            href: ~p"/admin/campaigns"
          }
          | tasks
        ]
      else
        tasks
      end

    # 库存警告
    low_inventory_campaigns = Enum.filter(campaigns, &has_low_inventory?(&1))

    tasks =
      if length(low_inventory_campaigns) > 0 do
        [
          %{
            title: "#{length(low_inventory_campaigns)} 個活動庫存不足",
            description: "部分獎品剩餘數量低於 20%，建議儘速補貨。",
            priority: :medium,
            badge: "P2",
            href: ~p"/admin/campaigns"
          }
          | tasks
        ]
      else
        tasks
      end

    # 邮件发送失败
    failed_emails_result = Emails.list_all_email_logs(status: "failed", limit: 100)

    failed_emails =
      failed_emails_result.items
      |> Enum.filter(fn log ->
        log.inserted_at && DateTime.compare(log.inserted_at, DateTime.add(now, -1, :day)) == :gt
      end)

    tasks =
      if length(failed_emails) > 0 do
        [
          %{
            title: "#{length(failed_emails)} 封郵件發送失敗",
            description: "過去 24 小時內有郵件發送失敗，請檢查 SES 配置。",
            priority: :high,
            badge: "P1",
            href: ~p"/admin/email-logs?status=failed"
          }
          | tasks
        ]
      else
        tasks
      end

    Enum.take(tasks, 5)
  end

  defp get_email_insights(now) do
    last24h = DateTime.add(now, -1, :day)

    # 过去 24 小时的邮件统计
    stats =
      from(el in Dobby.Emails.EmailLog,
        where: el.inserted_at >= ^last24h
      )
      |> Repo.all()

    sent_24h = Enum.count(stats, &(&1.status == "sent"))
    failed_24h = Enum.count(stats, &(&1.status == "failed"))
    pending_24h = Enum.count(stats, &(&1.status == "pending"))

    success_rate =
      if sent_24h + failed_24h > 0 do
        Float.round(sent_24h / (sent_24h + failed_24h) * 100, 1)
      else
        100.0
      end

    queue_fill_pct =
      if pending_24h > 0 do
        min(pending_24h * 2, 100)
      else
        0
      end

    %{
      total_sent: "#{format_number(sent_24h)}",
      # 邮件打开率需要邮件服务商提供，暂时不显示
      open_rate: "—",
      success_rate: "#{success_rate}%",
      queue_fill: "#{queue_fill_pct}%"
    }
  end

  defp build_notifications(campaigns, _now) do
    notifications = []

    # 配置缺失的活动
    incomplete_campaigns = Enum.filter(campaigns, &incomplete?(&1))

    notifications =
      if length(incomplete_campaigns) > 0 do
        [
          %{
            title: "#{length(incomplete_campaigns)} 個活動配置不完整",
            body: "部分活動缺少必要配置（日期、獎品等），請儘速完善。",
            action: "檢視活動",
            href: ~p"/admin/campaigns",
            level_color: "bg-amber-400"
          }
          | notifications
        ]
      else
        notifications
      end

    # 库存紧急警告
    critical_inventory = Enum.filter(campaigns, &has_critical_inventory?(&1))

    notifications =
      if length(critical_inventory) > 0 do
        [
          %{
            title: "獎品庫存緊急",
            body: "#{length(critical_inventory)} 個活動的獎品庫存低於 10%，請立即補貨。",
            action: "檢查庫存",
            href: ~p"/admin/campaigns",
            level_color: "bg-rose-500"
          }
          | notifications
        ]
      else
        notifications
      end

    # 邮件发送问题
    email_stats = Emails.get_email_log_stats([])

    notifications =
      if email_stats.failed > 0 && email_stats.total > 0 do
        failure_rate = email_stats.failed / email_stats.total * 100

        if failure_rate > 5 do
          [
            %{
              title: "郵件發送失敗率過高",
              body: "目前失敗率為 #{Float.round(failure_rate, 1)}%，請檢查 SES 配置。",
              action: "查看郵件日誌",
              href: ~p"/admin/email-logs",
              level_color: "bg-rose-500"
            }
            | notifications
          ]
        else
          notifications
        end
      else
        notifications
      end

    # 保护模式提醒
    protected_campaigns =
      Enum.filter(campaigns, fn campaign ->
        campaign.enable_protection && campaign.status == "active"
      end)

    notifications =
      if length(protected_campaigns) > 0 do
        [
          %{
            title: "#{length(protected_campaigns)} 個活動啟用保護模式",
            body: "保護模式可能影響兌獎率，請確認是否需要持續啟用。",
            action: "檢視設定",
            href: ~p"/admin/campaigns",
            level_color: "bg-amber-400"
          }
          | notifications
        ]
      else
        notifications
      end

    Enum.take(notifications, 4)
  end

  # Helper functions

  defp ending_soon?(campaign, now) do
    campaign.status == "active" && campaign.ends_at &&
      DateTime.compare(campaign.ends_at, now) == :gt &&
      DateTime.diff(campaign.ends_at, now, :hour) <= 72
  end

  defp has_low_inventory?(campaign) do
    campaign.prizes
    |> Enum.any?(fn prize ->
      if prize.total_quantity && prize.total_quantity > 0 do
        remaining = prize.remaining_quantity || 0
        percentage = remaining / prize.total_quantity * 100
        percentage < 20
      else
        false
      end
    end)
  end

  defp has_critical_inventory?(campaign) do
    campaign.prizes
    |> Enum.any?(fn prize ->
      if prize.total_quantity && prize.total_quantity > 0 do
        remaining = prize.remaining_quantity || 0
        percentage = remaining / prize.total_quantity * 100
        percentage < 10
      else
        false
      end
    end)
  end

  defp incomplete?(campaign) do
    campaign.status == "draft" &&
      (is_nil(campaign.starts_at) || is_nil(campaign.ends_at) || length(campaign.prizes) == 0)
  end

  defp calculate_inventory_percentage(campaign) do
    {total, remaining} =
      Enum.reduce(campaign.prizes, {0, 0}, fn prize, {t, r} ->
        if prize.total_quantity do
          {t + prize.total_quantity, r + (prize.remaining_quantity || 0)}
        else
          {t, r}
        end
      end)

    if total > 0 do
      Float.round(remaining / total * 100, 1)
    else
      100.0
    end
  end

  defp calculate_priority(campaign, now) do
    priority = 0

    priority =
      if ending_soon?(campaign, now), do: priority + 10, else: priority

    priority =
      if has_critical_inventory?(campaign), do: priority + 8, else: priority

    priority =
      if has_low_inventory?(campaign), do: priority + 5, else: priority

    priority =
      if campaign.status == "active", do: priority + 3, else: priority

    priority
  end

  defp status_label("active"), do: "運行中"
  defp status_label("draft"), do: "草稿"
  defp status_label("ended"), do: "已結束"
  defp status_label("disabled"), do: "已停用"
  defp status_label(_), do: "未知"

  defp status_color("active"), do: "bg-emerald-100 text-emerald-800"
  defp status_color("draft"), do: "bg-slate-100 text-slate-800"
  defp status_color("ended"), do: "bg-slate-100 text-slate-600"
  defp status_color("disabled"), do: "bg-amber-100 text-amber-800"
  defp status_color(_), do: "bg-slate-100 text-slate-600"

  defp status_badge_variant("bg-emerald-100 text-emerald-800"), do: "success"
  defp status_badge_variant("bg-slate-100 text-slate-800"), do: "default"
  defp status_badge_variant("bg-slate-100 text-slate-600"), do: "default"
  defp status_badge_variant("bg-amber-100 text-amber-800"), do: "warning"
  defp status_badge_variant(_), do: "default"

  defp delta_badge_variant("bg-emerald-50 text-emerald-700"), do: "success"
  defp delta_badge_variant("bg-amber-50 text-amber-700"), do: "warning"
  defp delta_badge_variant("bg-slate-50 text-slate-700"), do: "default"
  defp delta_badge_variant(_), do: "default"

  defp task_priority_badge_variant(:high), do: "error"
  defp task_priority_badge_variant(:medium), do: "warning"
  defp task_priority_badge_variant(:low), do: "default"
  defp task_priority_badge_variant(_), do: "default"

  defp format_time_ago(datetime, now) do
    diff_minutes = DateTime.diff(now, datetime, :minute)

    cond do
      diff_minutes < 1 -> "剛剛"
      diff_minutes < 60 -> "#{diff_minutes} 分鐘前"
      diff_minutes < 1440 -> "#{div(diff_minutes, 60)} 小時前"
      true -> "#{div(diff_minutes, 1440)} 天前"
    end
  end

  defp format_number(num) when num >= 1000 do
    "#{Float.round(num / 1000, 1)}k"
  end

  defp format_number(num), do: "#{num}"
end
