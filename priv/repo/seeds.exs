# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Dobby.Repo.insert!(%Dobby.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Dobby.Repo
alias Dobby.Accounts
alias Dobby.PrizeLibrary

IO.puts("🌱 开始创建种子数据...")
IO.puts("")

# ============================================
# 创建管理员账号
# ============================================
IO.puts("👤 创建管理员账号...")

admin_email = "admin@dobby.com"
admin_password = System.get_env("ADMIN_PASSWORD") || "Admin123!"

case Accounts.get_admin_by_email(admin_email) do
  nil ->
    case Accounts.register_admin(%{
           email: admin_email,
           password: admin_password,
           name: "系统管理员",
           role: "admin"
         }) do
      {:ok, admin} ->
        IO.puts("  ✅ 创建管理员成功: #{admin.email}")
        IO.puts("  📧 邮箱: #{admin.email}")
        IO.puts("  🔑 密码: #{admin_password}")
        IO.puts("  ⚠️  请在生产环境中修改默认密码！")

      {:error, changeset} ->
        IO.puts("  ❌ 创建管理员失败:")
        IO.inspect(changeset.errors, label: "错误")
    end

  existing_admin ->
    IO.puts("  ℹ️  管理员已存在: #{existing_admin.email}")
end

IO.puts("")

# ============================================
# 创建奖品模板
# ============================================
IO.puts("🎁 创建奖品模板...")

prize_templates = [
  %{
    name: "iPhone 15 Pro",
    prize_type: "physical",
    description: "最新款 iPhone 15 Pro，256GB 存储",
    redemption_guide: "中奖后请在30天内填写收货地址，我们会在7个工作日内发货。"
  },
  %{
    name: "iPad Air",
    prize_type: "physical",
    description: "iPad Air 第5代，64GB 存储",
    redemption_guide: "中奖后请在30天内填写收货地址，我们会在7个工作日内发货。"
  },
  %{
    name: "AirPods Pro",
    prize_type: "physical",
    description: "Apple AirPods Pro 第2代，主动降噪",
    redemption_guide: "中奖后请在30天内填写收货地址，我们会在7个工作日内发货。"
  },
  %{
    name: "100元优惠券",
    prize_type: "virtual",
    description: "适用于全品类商品，有效期90天",
    redemption_guide: "中奖后系统会自动发放优惠券到您的账户，可在购物时直接使用。"
  },
  %{
    name: "50元优惠券",
    prize_type: "virtual",
    description: "适用于全品类商品，有效期60天",
    redemption_guide: "中奖后系统会自动发放优惠券到您的账户，可在购物时直接使用。"
  },
  %{
    name: "20元优惠券",
    prize_type: "virtual",
    description: "适用于全品类商品，有效期30天",
    redemption_guide: "中奖后系统会自动发放优惠券到您的账户，可在购物时直接使用。"
  },
  %{
    name: "10元优惠券",
    prize_type: "virtual",
    description: "适用于全品类商品，有效期30天",
    redemption_guide: "中奖后系统会自动发放优惠券到您的账户，可在购物时直接使用。"
  },
  %{
    name: "谢谢参与",
    prize_type: "no_prize",
    description: "感谢参与抽奖活动",
    redemption_guide: "感谢您的参与，请继续关注我们的活动！"
  }
]

{created_count, skipped_count} =
  Enum.reduce(prize_templates, {0, 0}, fn template_attrs, {created, skipped} ->
    case PrizeLibrary.list_templates(%{search: template_attrs.name}) do
      %{items: []} ->
        case PrizeLibrary.create_template(template_attrs) do
          {:ok, template} ->
            IO.puts("  ✅ #{template.name} (#{template.prize_type})")
            {created + 1, skipped}

          {:error, changeset} ->
            IO.puts("  ❌ 创建失败: #{template_attrs.name}")
            IO.inspect(changeset.errors, label: "错误")
            {created, skipped}
        end

      _ ->
        IO.puts("  ℹ️  已存在: #{template_attrs.name}")
        {created, skipped + 1}
    end
  end)

IO.puts("  📊 创建: #{created_count} 个，跳过: #{skipped_count} 个")
IO.puts("")

# ============================================
# 完成
# ============================================
IO.puts("✅ 种子数据创建完成！")
IO.puts("")
IO.puts("📝 默认管理员登录信息：")
IO.puts("   邮箱: #{admin_email}")
IO.puts("   密码: #{admin_password}")
IO.puts("")
IO.puts("⚠️  生产环境注意事项：")
IO.puts("   1. 请立即修改管理员密码")
IO.puts("   2. 可以通过环境变量 ADMIN_PASSWORD 设置初始密码")
IO.puts("   3. 运行: ADMIN_PASSWORD=your_secure_password mix run priv/repo/seeds.exs")
