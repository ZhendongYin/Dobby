defmodule DobbyWeb.Public.ScratchLive do
  use DobbyWeb, :live_view

  alias Dobby.Lottery
  alias Dobby.Campaigns
  alias Dobby.Campaigns.Prize
  alias Ecto.NoResultsError

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :show_prize_modal, false)}
  end

  def handle_params(
        %{"campaign_id" => campaign_id, "transaction_number" => transaction_number},
        _url,
        socket
      ) do
    with {:ok, campaign} <- fetch_campaign(campaign_id) do
      tx_record = Lottery.get_transaction_number_by_code(transaction_number)

      cond do
        tx_record && tx_record.campaign_id != campaign.id ->
          {:noreply,
           invalid_access(
             socket,
             "此抽獎碼不屬於本活動。",
             campaign: campaign
           )}

        tx_record && tx_record.is_used ->
          winning_record = Lottery.get_winning_record_by_transaction_number(tx_record.id)
          prize = if winning_record, do: Campaigns.get_prize!(winning_record.prize_id), else: nil
          prizes = campaign_prizes(campaign.id)

          # 根据是否已刮开和状态来决定显示什么
          state =
            cond do
              # 已刮开且未提交信息，显示结果
              tx_record.is_scratched && winning_record &&
                  winning_record.status == "pending_submit" ->
                :revealed

              # 已使用但未刮开，显示刮开界面
              !tx_record.is_scratched && winning_record &&
                  winning_record.status == "pending_submit" ->
                :scratching

              # 其他情况显示已使用
              true ->
                :already_used
            end

          {:noreply,
           socket
           |> assign(:transaction_code, transaction_number)
           |> assign(:transaction_record, tx_record)
           |> assign(:campaign, campaign)
           |> assign(:prizes, prizes)
           |> assign(:show_prize_modal, false)
           |> assign(:winning_record, winning_record)
           |> assign(:prize, prize || default_prize())
           |> assign(:state, state)
           |> assign(:scratch_progress, if(state == :revealed, do: 1.0, else: 0.0))}

        true ->
          prizes = campaign_prizes(campaign.id)

          socket =
            socket
            |> assign(:transaction_code, transaction_number)
            |> assign(:transaction_record, tx_record)
            |> assign(:campaign, campaign)
            |> assign(:prizes, prizes)
            |> assign(:show_prize_modal, false)
            |> assign(:winning_record, nil)
            |> assign(:prize, default_prize())
            |> assign(:state, :processing)
            |> assign(:scratch_progress, 0.0)

          # Auto-validate immediately when connected
          if connected?(socket) do
            Process.send_after(
              self(),
              {:auto_validate,
               %{
                 transaction_code: transaction_number,
                 campaign_id: campaign.id,
                 ip: get_remote_ip(socket),
                 ua: get_user_agent(socket)
               }},
              100
            )
          end

          {:noreply, socket}
      end
    else
      {:error, :campaign_not_found} ->
        {:noreply, invalid_access(socket, "找不到此活動。")}
    end
  end

  def handle_event("update_progress", %{"progress" => progress}, socket) do
    # progress 可能已经是 float 或字符串，需要安全转换
    progress_float =
      cond do
        is_float(progress) -> progress
        is_binary(progress) -> String.to_float(progress)
        true -> progress / 1.0
      end

    # 如果达到 50% 且当前状态是 :scratching，标记为已刮开并切换到 :revealed
    {new_state, updated_tx_record} =
      if progress_float >= 0.5 and socket.assigns.state == :scratching do
        # 更新数据库中的 is_scratched 状态
        tx_record = socket.assigns.transaction_record

        if tx_record && !tx_record.is_scratched do
          case Lottery.update_transaction_number(tx_record, %{is_scratched: true}) do
            {:ok, updated_tx} -> {:revealed, updated_tx}
            {:error, _} -> {:revealed, tx_record}
          end
        else
          {:revealed, tx_record}
        end
      else
        {socket.assigns.state, socket.assigns.transaction_record}
      end

    updated_winning_record =
      if new_state == :revealed and socket.assigns.winning_record && socket.assigns.prize &&
           prize_type(socket.assigns.prize) == "no_prize" &&
           socket.assigns.winning_record.status == "pending_submit" do
        case Lottery.update_winning_record(socket.assigns.winning_record, %{status: "fulfilled"}) do
          {:ok, winning_record} -> winning_record
          {:error, _} -> socket.assigns.winning_record
        end
      else
        socket.assigns.winning_record
      end

    {:noreply,
     socket
     |> assign(:scratch_progress, progress_float)
     |> assign(:state, new_state)
     |> assign(:transaction_record, updated_tx_record)
     |> assign(:winning_record, updated_winning_record)}
  end

  def handle_event("submit_info", _params, socket) do
    if socket.assigns.winning_record && socket.assigns.prize &&
         prize_type(socket.assigns.prize) != "no_prize" do
      {:noreply, push_navigate(socket, to: ~p"/submit/#{socket.assigns.winning_record.id}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_prize_modal", _params, socket) do
    {:noreply, assign(socket, :show_prize_modal, true)}
  end

  def handle_event("close_prize_modal", _params, socket) do
    {:noreply, assign(socket, :show_prize_modal, false)}
  end

  def handle_info(
        {:auto_validate, %{transaction_code: tx_code, campaign_id: campaign_id, ip: ip, ua: ua}},
        socket
      ) do
    require Logger
    Logger.debug("Auto-validating transaction: #{tx_code}")

    case Lottery.draw_and_record(tx_code, campaign_id, ip, ua) do
      {:ok, %{winning_record: winning_record, prize: prize, transaction_number: tx_number}} ->
        Logger.debug("Validation successful, transitioning to scratching state")

        {:noreply,
         socket
         |> assign(:winning_record, winning_record)
         |> assign(:prize, prize)
         |> assign(:transaction_record, tx_number)
         |> assign(:state, :scratching)}

      {:error, reason} ->
        Logger.debug("Validation failed: #{inspect(reason)}")

        {:noreply,
         invalid_access(socket, humanize_lottery_error(reason),
           campaign: socket.assigns[:campaign]
         )}
    end
  end

  defp get_remote_ip(socket) do
    case get_in(socket.private, [:connect_info, :peer_data, :address]) do
      {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
      {a, b, c, d, e, f, g, h} -> "#{a}:#{b}:#{c}:#{d}:#{e}:#{f}:#{g}:#{h}"
      nil -> "127.0.0.1"
      other -> to_string(other)
    end
  end

  defp get_user_agent(socket) do
    get_in(socket.private, [:connect_info, :user_agent]) || "Unknown"
  end

  defp fetch_campaign(nil), do: {:error, :campaign_not_found}

  defp fetch_campaign(campaign_id) do
    try do
      {:ok, Campaigns.get_campaign!(campaign_id)}
    rescue
      NoResultsError ->
        {:error, :campaign_not_found}
    end
  end

  defp invalid_access(socket, message, opts \\ []) do
    campaign = Keyword.get(opts, :campaign) || socket.assigns[:campaign]

    socket =
      socket
      |> put_flash(:error, message)

    case campaign do
      %{id: id} when not is_nil(id) ->
        redirect(socket, to: ~p"/campaigns/#{id}/invalid-code")

      _ ->
        redirect(socket, to: ~p"/")
    end
  end

  defp humanize_lottery_error(:campaign_inactive), do: "此活動未在進行中。"
  defp humanize_lottery_error(:campaign_not_started), do: "此活動尚未開始。"
  defp humanize_lottery_error(:campaign_ended), do: "此活動已結束。"

  defp humanize_lottery_error(:transaction_already_used),
    do: "此抽獎碼已使用過。"

  defp humanize_lottery_error(:transaction_campaign_mismatch),
    do: "此抽獎碼不屬於本活動。"

  defp humanize_lottery_error(:code_not_registered),
    do: "此抽獎碼不在本活動名單內，請確認是否已完成匯入。"

  defp humanize_lottery_error({:transaction_verification_failed, reason}),
    do: "交易驗證失敗：#{inspect(reason)}"

  defp humanize_lottery_error({:transaction_persist_error, changeset}),
    do: "無法建立抽獎碼：#{inspect(changeset.errors)}"

  defp humanize_lottery_error(other),
    do: "無法完成抽獎：#{inspect(other)}"

  defp default_prize do
    %Prize{prize_type: "no_prize", name: "", description: nil}
  end

  defp format_date(nil), do: "-"

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp campaign_background_image_url(%{background_image_url: url}) when is_binary(url) do
    case String.trim(url) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp campaign_background_image_url(_), do: nil

  defp hero_css_vars(campaign) do
    "--accent-color: #{accent_color(campaign)};"
  end

  defp campaign_prizes(campaign_id) do
    Campaigns.list_prizes(campaign_id, %{page: 1, page_size: 200}).items
  end

  defp visible_prizes(prizes) when is_list(prizes) do
    Enum.reject(prizes, fn prize -> prize_type(prize) == "no_prize" end)
  end

  defp visible_prizes(_), do: []

  defp accent_color(%{theme_color: color}) when is_binary(color) do
    case String.trim(color) do
      "" -> "#f472b6"
      trimmed -> trimmed
    end
  end

  defp accent_color(_), do: "#f472b6"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :public}}>
      <div
        class="relative min-h-screen text-white overflow-hidden"
        style={hero_css_vars(@campaign)}
      >
        <%= if bg_url = campaign_background_image_url(@campaign) do %>
          <div class="absolute inset-0">
            <img
              src={bg_url}
              alt="Campaign background"
              class="h-full w-full object-cover"
              decoding="async"
              loading="lazy"
            />
          </div>
          <div class="absolute inset-0 bg-slate-950/90 backdrop-blur-[2px]"></div>
        <% else %>
          <div class="absolute inset-0 opacity-30 bg-[radial-gradient(circle_at_top,_rgba(120,119,198,0.35),_transparent_55%)]">
          </div>
          <div class="absolute inset-0 opacity-20 bg-[radial-gradient(circle_at_bottom,_rgba(14,165,233,0.35),_transparent_50%)]">
          </div>
        <% end %>

        <div class="relative max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
          <div class="flex flex-col gap-6 lg:flex-row lg:items-center lg:justify-between">
            <div class="space-y-5">
              <div class="inline-flex items-center gap-2 rounded-full bg-white/10 px-4 py-1 text-xs tracking-[0.35em] text-white/90 uppercase">
                <.icon name="hero-sparkles" class="h-4 w-4 text-amber-200" /> 刮奖进行中
              </div>
              <div class="space-y-3">
                <h1 class="text-4xl md:text-5xl font-black text-white tracking-tight drop-shadow-[0_20px_50px_rgba(0,0,0,.45)]">
                  {@campaign.name}
                </h1>
                <p :if={@campaign.description} class="text-lg text-white/95 max-w-2xl leading-relaxed">
                  {@campaign.description}
                </p>
              </div>
              <button
                type="button"
                phx-click="open_prize_modal"
                class="inline-flex items-center gap-2 rounded-full px-5 py-2 font-semibold shadow-lg hover:-translate-y-0.5 transition"
                style="background: var(--accent-color); color: #0f172a;"
              >
                查看奖品列表 <.icon name="hero-arrow-down" class="h-4 w-4" />
              </button>
            </div>
            <div class="bg-white/10 border border-white/20 rounded-2xl px-6 py-5 shadow-2xl backdrop-blur">
              <p class="text-xs uppercase tracking-[0.3em] text-white/90 mb-2">当前状态</p>
              <p class="text-lg font-semibold text-emerald-100 flex items-center gap-2">
                <span class="h-2.5 w-2.5 rounded-full bg-emerald-300 animate-pulse"></span> 即刻开启
              </p>
              <p class="text-xs text-white/90 mt-1">
                截止 {format_date(@campaign.ends_at)}
              </p>
            </div>
          </div>

          <div class="bg-white/10 border border-white/15 rounded-[32px] shadow-2xl backdrop-blur-2xl p-6 sm:p-10">
            <%= cond do %>
              <% @state == :processing -> %>
                <div class="text-center space-y-6">
                  <div class="inline-flex items-center gap-2 rounded-full bg-white/10 text-white/95 px-4 py-1.5 text-sm">
                    <div class="h-2 w-2 rounded-full bg-indigo-300 animate-pulse"></div>
                    验证中...
                  </div>
                  <p class="text-2xl font-semibold text-white">正在確認抽獎碼</p>
                  <p class="text-slate-100">请稍候，几秒钟即可完成。</p>
                  <div class="flex justify-center">
                    <div class="h-12 w-12 border-4 border-white/30 border-t-white rounded-full animate-spin">
                    </div>
                  </div>
                </div>
              <% @state == :scratching -> %>
                <div class="space-y-5">
                  <div class="relative">
                    <div class="absolute -top-6 left-0 inline-flex items-center gap-2 rounded-full bg-black/40 px-4 py-1 text-xs uppercase tracking-[0.35em] text-white/95">
                      <.icon name="hero-hand-raised" class="h-4 w-4 text-pink-200" /> 滑动刮开
                    </div>
                    <div
                      id="scratch-card"
                      phx-hook="ScratchCard"
                      phx-update="ignore"
                      data-prize-name={(@prize && prize_name(@prize)) || ""}
                      data-prize-type={(@prize && prize_type(@prize)) || ""}
                      class="relative w-full h-72 rounded-[32px] overflow-hidden border border-white/25 shadow-[0_25px_120px_rgba(0,0,0,.45)] cursor-crosshair"
                    >
                      <div class="absolute inset-0 rounded-[32px]" style="z-index: 0;">
                        <%= if @prize && prize_image_url(@prize) do %>
                          <img
                            src={prize_image_url(@prize)}
                            alt={prize_name(@prize)}
                            class="w-full h-full object-cover rounded-[32px]"
                          />
                        <% end %>
                        <div class="absolute inset-0 flex flex-col items-center justify-center text-center px-6">
                          <%= if @prize && @prize.prize_type == "no_prize" do %>
                            <div class="bg-white/95 backdrop-blur-sm rounded-2xl px-6 py-4 shadow-lg">
                              <p class="text-2xl font-bold text-slate-700 mb-2">谢谢参与</p>
                              <p class="text-slate-500">
                                {@campaign.no_prize_message || "继续关注活动，还有更多机会！"}
                              </p>
                            </div>
                          <% else %>
                            <%= if @prize do %>
                              <div class="bg-white/95 backdrop-blur-sm rounded-2xl px-6 py-4 shadow-lg">
                                <p class="text-4xl font-black text-fuchsia-600 mb-3">恭喜中奖</p>
                                <p class="text-2xl text-slate-800 font-semibold">{@prize.name}</p>
                                <p :if={@prize.description} class="mt-2 text-slate-500 max-w-sm">
                                  {@prize.description}
                                </p>
                              </div>
                            <% else %>
                              <div class="bg-white/95 backdrop-blur-sm rounded-2xl px-6 py-4 shadow-lg">
                                <p class="text-2xl font-bold text-slate-700 mb-2">加载中...</p>
                              </div>
                            <% end %>
                          <% end %>
                        </div>
                      </div>
                      <div
                        class="absolute inset-0 bg-gradient-to-br from-slate-300 via-slate-200 to-slate-300 rounded-[32px]"
                        style="z-index: 998; pointer-events: none;"
                        id="scratch-overlay-backup"
                      >
                      </div>
                    </div>
                    <div class="mt-6 flex items-center justify-between text-sm text-white/95">
                      <div class="flex items-center gap-2">
                        <div class="h-2 w-2 rounded-full bg-pink-300 animate-pulse"></div>
                        刮开进度
                      </div>
                      <span class="font-semibold text-white">
                        {Float.round(@scratch_progress * 100, 1)}%
                      </span>
                    </div>
                    <div class="w-full h-2 bg-white/10 rounded-full overflow-hidden">
                      <div
                        class="h-full rounded-full transition-all duration-500"
                        style={
                          "width: #{Float.round(@scratch_progress * 100, 1)}%; background: linear-gradient(90deg, var(--accent-color), rgba(255,255,255,0.7));"
                        }
                      >
                      </div>
                    </div>
                  </div>
                </div>
              <% @state == :revealed -> %>
                <%= if @prize && @prize.prize_type == "no_prize" do %>
                  <div class="max-w-3xl mx-auto">
                    <div class="rounded-[28px] border border-white/20 bg-gradient-to-b from-white/10 to-white/5 p-8 sm:p-10 text-center space-y-5">
                      <div class="mx-auto h-14 w-14 rounded-full bg-white/15 flex items-center justify-center">
                        <.icon name="hero-face-smile" class="h-8 w-8 text-amber-200" />
                      </div>
                      <p class="text-4xl font-black text-white drop-shadow-lg">谢谢参与</p>
                      <p class="text-slate-100 text-lg">
                        {@campaign.no_prize_message || "关注活动，下次好运一定属于你。"}
                      </p>
                      <div class="pt-2 flex flex-col sm:flex-row items-center justify-center gap-3">
                        <button
                          type="button"
                          phx-click="open_prize_modal"
                          class="inline-flex items-center gap-2 rounded-full bg-white text-slate-900 px-6 py-3 font-semibold shadow-lg hover:-translate-y-0.5 transition"
                        >
                          查看奖品列表 <.icon name="hero-gift" class="h-4 w-4" />
                        </button>
                      </div>
                    </div>
                  </div>
                <% else %>
                  <div class="grid gap-8 lg:grid-cols-2 items-center">
                    <div class="space-y-6 text-center lg:text-left relative">
                      <div class="absolute -top-6 -left-4 w-20 h-20 bg-pink-400/20 blur-3xl rounded-full">
                      </div>
                      <div class="space-y-3">
                        <p class="text-4xl font-black text-transparent bg-clip-text bg-gradient-to-r from-amber-300 via-rose-300 to-fuchsia-400 drop-shadow-xl">
                          🎉 恭喜中奖！
                        </p>
                        <p class="text-3xl text-white font-semibold">{@prize && @prize.name}</p>
                        <p :if={@prize && @prize.description} class="text-slate-100">
                          {@prize.description}
                        </p>
                      </div>
                      <div class="flex flex-col sm:flex-row gap-3 pt-2">
                        <button
                          phx-click="submit_info"
                          class="flex-1 inline-flex items-center justify-center rounded-full bg-white text-slate-900 px-6 py-3 font-semibold shadow-lg hover:-translate-y-0.5 transition"
                        >
                          填写领奖信息
                        </button>
                        <button
                          class="flex-1 inline-flex items-center justify-center rounded-full border border-white/30 text-white/95 px-6 py-3"
                          disabled
                        >
                          保存截图
                        </button>
                      </div>
                    </div>
                    <div class="relative">
                      <div
                        class="absolute inset-0 pointer-events-none"
                        style="background-image: radial-gradient(circle at 20% 20%, rgba(248,113,113,0.2), transparent 40%), radial-gradient(circle at 80% 0%, rgba(129,140,248,0.2), transparent 45%), radial-gradient(circle at 50% 100%, rgba(52,211,153,0.2), transparent 35%);"
                      >
                      </div>
                      <img
                        :if={@prize && @prize.image_url}
                        src={@prize.image_url}
                        alt={@prize.name}
                        class="relative w-full rounded-[32px] border border-white/25 shadow-[0_25px_120px_rgba(0,0,0,.45)] object-cover"
                      />
                      <div
                        :if={!@prize || !@prize.image_url}
                        class="relative w-full h-64 rounded-[32px] border border-dashed border-white/30 flex flex-col items-center justify-center gap-2"
                      >
                        <.icon name="hero-gift" class="h-10 w-10 text-white/90" />
                        <span class="text-white/95">奖品信息加载中</span>
                      </div>
                    </div>
                  </div>
                <% end %>
              <% @state == :already_used -> %>
                <div class="text-center space-y-6">
                  <div class="inline-flex items-center gap-2 rounded-full bg-white/10 text-amber-200 px-4 py-1.5 text-sm">
                    <.icon name="hero-information-circle" class="h-4 w-4" /> 抽獎碼已使用
                  </div>
                  <p class="text-2xl font-semibold text-white">這張抽獎碼已經刮開過啦</p>
                  <%= if @prize do %>
                    <p class="text-slate-100">
                      上次惊喜是 <span class="font-semibold text-white">{@prize.name}</span>
                    </p>
                    <%= if @prize.prize_type != "no_prize" && @winning_record && @winning_record.status == "pending_submit" do %>
                      <button
                        phx-click="submit_info"
                        class="inline-flex items-center justify-center px-6 py-3 rounded-full bg-white text-slate-900 font-semibold shadow-lg"
                      >
                        继续完成领奖
                      </button>
                    <% end %>
                  <% end %>
                  <.link
                    navigate={~p"/"}
                    class="inline-flex items-center gap-2 rounded-full border border-white/20 px-4 py-2 text-white/95 hover:bg-white/10 transition text-sm"
                  >
                    <.icon name="hero-arrow-uturn-left" class="h-4 w-4" /> 返回首页
                  </.link>
                </div>
              <% true -> %>
                <div class="text-center space-y-4">
                  <p class="text-2xl font-semibold text-rose-300">出错了</p>
                  <p class="text-slate-100">请刷新页面或稍后再试。</p>
                </div>
            <% end %>
          </div>

          <%= if @show_prize_modal do %>
            <div
              id="prize-list-modal"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 sm:p-6"
              role="dialog"
              aria-modal="true"
              aria-label="奖品列表"
            >
              <div
                class="absolute inset-0 bg-black/70 backdrop-blur-sm"
                phx-click="close_prize_modal"
              >
              </div>

              <section class="relative w-full max-w-4xl bg-slate-900/95 border border-white/20 rounded-[28px] shadow-2xl p-6 sm:p-8">
                <div class="flex items-center justify-between gap-3 mb-5">
                  <h2 class="text-2xl font-black text-white tracking-tight">奖品列表</h2>
                  <div class="flex items-center gap-2">
                    <span class="text-xs rounded-full px-3 py-1 bg-white/15 text-white/90">
                      共 {length(visible_prizes(@prizes))} 项
                    </span>
                    <button
                      type="button"
                      phx-click="close_prize_modal"
                      class="inline-flex items-center justify-center rounded-full border border-white/30 text-white h-8 w-8 hover:bg-white/10 transition"
                      aria-label="关闭奖品列表"
                    >
                      <.icon name="hero-x-mark" class="h-4 w-4" />
                    </button>
                  </div>
                </div>

                <%= if Enum.empty?(visible_prizes(@prizes)) do %>
                  <p class="text-white/85">本活动暂未配置可展示奖品。</p>
                <% else %>
                  <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 max-h-[60vh] overflow-y-auto pr-1">
                    <article
                      :for={prize <- visible_prizes(@prizes)}
                      class="rounded-2xl border border-white/20 bg-black/20 overflow-hidden"
                    >
                      <div class="h-36 w-full bg-white/5">
                        <img
                          :if={prize_image_url(prize)}
                          src={prize_image_url(prize)}
                          alt={prize_name(prize) || "Prize image"}
                          class="h-full w-full object-cover"
                        />
                      </div>
                      <div class="p-4 space-y-2">
                        <div class="flex items-center justify-between gap-2">
                          <p class="font-semibold text-white truncate">{prize_name(prize) || "未命名奖品"}</p>
                          <span
                            class="shrink-0 text-[11px] rounded-full px-2 py-0.5 border border-white/20 text-white/85"
                          >
                            {prize_type(prize) || "-"}
                          </span>
                        </div>
                        <p class="text-sm text-white/75 line-clamp-2">{prize.description || "敬请期待。"}</p>
                      </div>
                    </article>
                  </div>
                <% end %>
              </section>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # 辅助函数：从模板或 prize 获取字段值
  defp prize_name(%{source_template: %{name: name}}) when not is_nil(name), do: name
  defp prize_name(%{name: name}), do: name
  defp prize_name(_), do: nil

  defp prize_image_url(%{source_template: %{image_url: url}}) when not is_nil(url), do: url
  defp prize_image_url(%{image_url: url}), do: url
  defp prize_image_url(_), do: nil

  defp prize_type(%{source_template: %{prize_type: type}}) when not is_nil(type), do: type
  defp prize_type(%{prize_type: type}), do: type
  defp prize_type(_), do: nil
end
