# 邮件发送功能快速测试脚本
# 使用方法：在 IEx 中运行 `Code.eval_file("test_email.exs")`

alias Dobby.{Repo, Campaigns, Lottery, Emails}
alias Dobby.Campaigns.{Campaign, Prize}
alias Dobby.Lottery.{WinningRecord, TransactionNumber}

# 1. 获取或创建一个测试活动
IO.puts("\n=== 步骤 1: 查找或创建测试活动 ===")

campaign =
  case Campaigns.list_campaigns() |> List.first() do
    nil ->
      IO.puts("创建新的测试活动...")

      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "邮件测试活动",
          description: "用于测试邮件发送功能",
          status: "active",
          starts_at: DateTime.add(DateTime.utc_now(), -1, :day),
          ends_at: DateTime.add(DateTime.utc_now(), 30, :day),
          theme_color: "#4338ca",
          admin_id: Repo.all(Dobby.Accounts.Admin) |> List.first() |> Map.get(:id)
        })

      campaign

    campaign ->
      IO.puts("使用现有活动: #{campaign.name}")
      campaign
  end

# 2. 确保活动有奖品
IO.puts("\n=== 步骤 2: 检查奖品 ===")
prizes = Campaigns.list_prizes(campaign.id)

prize =
  case Enum.reject(prizes, &(&1.prize_type == "no_prize")) |> List.first() do
    nil ->
      IO.puts("创建测试奖品...")

      {:ok, prize} =
        Campaigns.create_prize(%{
          campaign_id: campaign.id,
          name: "测试奖品",
          description: "这是一个测试奖品",
          prize_type: "physical",
          total_quantity: 100,
          remaining_quantity: 100,
          probability_mode: "percentage",
          probability: Decimal.new("10.00")
        })

      prize

    prize ->
      IO.puts("使用现有奖品: #{prize.name}")
      prize
  end

# 3. 确保有邮件模板
IO.puts("\n=== 步骤 3: 检查邮件模板 ===")
template = Emails.ensure_default_template!(campaign)
IO.puts("邮件模板: #{template.name}")

# 4. 创建测试中奖记录
IO.puts("\n=== 步骤 4: 创建测试中奖记录 ===")
transaction_number = "TEST-#{System.system_time(:second)}"

{:ok, tx} =
  Lottery.create_transaction_number(%{
    transaction_number: transaction_number,
    campaign_id: campaign.id,
    is_used: true
  })

{:ok, winning_record} =
  Lottery.create_winning_record(%{
    transaction_number_id: tx.id,
    prize_id: prize.id,
    campaign_id: campaign.id,
    name: "测试用户",
    email: "test@example.com",
    status: "pending_process"
  })

IO.puts("创建中奖记录: #{winning_record.id}")
IO.puts("邮箱: #{winning_record.email}")

# 5. 发送邮件
IO.puts("\n=== 步骤 5: 发送邮件 ===")

case Emails.send_winning_notification(winning_record) do
  {:ok, updated_record} ->
    IO.puts("✅ 邮件发送成功！")
    IO.puts("邮件发送时间: #{inspect(updated_record.email_sent_at)}")
    IO.puts("\n📧 请在浏览器中访问 http://localhost:4000/dev/mailbox 查看邮件")

  {:error, reason} ->
    IO.puts("❌ 邮件发送失败: #{inspect(reason)}")
end

IO.puts("\n=== 测试完成 ===")
IO.puts("活动 ID: #{campaign.id}")
IO.puts("中奖记录 ID: #{winning_record.id}")
IO.puts("交易码: #{transaction_number}")
