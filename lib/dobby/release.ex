defmodule Dobby.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :dobby

  alias Dobby.Accounts
  alias Dobby.PrizeLibrary

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def seed do
    load_app()

    IO.puts("🌱 开始创建种子数据...")
    IO.puts("")

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seed_admin()
          seed_prize_templates()
          Dobby.Seeds.EmailTemplatesAndCampaigns.run()
        end)
    end

    IO.puts("✅ 种子数据创建完成！")
  end

  defp seed_admin do
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
  end

  defp seed_prize_templates do
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
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
