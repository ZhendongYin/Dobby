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

    IO.puts("🌱 开始初始化演示数据…")
    IO.puts("")

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seed_admin()
          seed_prize_templates()
          Dobby.Seeds.EmailTemplatesAndCampaigns.run()
        end)
    end

    IO.puts("✅ 演示数据初始化完成！")
  end

  defp seed_admin do
    IO.puts("👤 建立管理員帳號...")

    admin_email = "admin@dobby.com"
    admin_password = System.get_env("ADMIN_PASSWORD") || "Admin123!"

    case Accounts.get_admin_by_email(admin_email) do
      nil ->
        case Accounts.register_admin(%{
               email: admin_email,
               password: admin_password,
               name: "系統管理員",
               role: "admin"
             }) do
          {:ok, admin} ->
            IO.puts("  ✅ 建立管理員成功: #{admin.email}")
            IO.puts("  📧 信箱: #{admin.email}")
            IO.puts("  🔑 密碼: #{admin_password}")
            IO.puts("  ⚠️  請在生產環境中修改預設密碼！")

          {:error, changeset} ->
            IO.puts("  ❌ 建立管理員失敗:")
            IO.inspect(changeset.errors, label: "錯誤")
        end

      existing_admin ->
        IO.puts("  ℹ️  管理員已存在: #{existing_admin.email}")
    end

    IO.puts("")
  end

  defp seed_prize_templates do
    IO.puts("🎁 建立獎品模板...")

    prize_templates = [
      %{
        name: "iPhone 15 Pro",
        prize_type: "physical",
        description: "最新款 iPhone 15 Pro，256GB 儲存空間",
        redemption_guide: "中獎後請在 30 天內填寫收貨地址，我們會在 7 個工作天內出貨。"
      },
      %{
        name: "iPad Air",
        prize_type: "physical",
        description: "iPad Air 第 5 代，64GB 儲存空間",
        redemption_guide: "中獎後請在 30 天內填寫收貨地址，我們會在 7 個工作天內出貨。"
      },
      %{
        name: "AirPods Pro",
        prize_type: "physical",
        description: "Apple AirPods Pro 第 2 代，主動降噪",
        redemption_guide: "中獎後請在 30 天內填寫收貨地址，我們會在 7 個工作天內出貨。"
      },
      %{
        name: "100元優惠券",
        prize_type: "virtual",
        description: "適用於全品類商品，有效期 90 天",
        redemption_guide: "中獎後系統會自動發放優惠券到您的帳戶，可在購物時直接使用。"
      },
      %{
        name: "50元優惠券",
        prize_type: "virtual",
        description: "適用於全品類商品，有效期 60 天",
        redemption_guide: "中獎後系統會自動發放優惠券到您的帳戶，可在購物時直接使用。"
      },
      %{
        name: "20元優惠券",
        prize_type: "virtual",
        description: "適用於全品類商品，有效期 30 天",
        redemption_guide: "中獎後系統會自動發放優惠券到您的帳戶，可在購物時直接使用。"
      },
      %{
        name: "10元優惠券",
        prize_type: "virtual",
        description: "適用於全品類商品，有效期 30 天",
        redemption_guide: "中獎後系統會自動發放優惠券到您的帳戶，可在購物時直接使用。"
      },
      %{
        name: "謝謝參與",
        prize_type: "no_prize",
        description: "感谢参与抽奖活动",
        redemption_guide: "感謝您的參與，請持續關注我們的活動！"
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
                IO.puts("  ❌ 建立失敗: #{template_attrs.name}")
                IO.inspect(changeset.errors, label: "錯誤")
                {created, skipped}
            end

          _ ->
            IO.puts("  ℹ️  已存在: #{template_attrs.name}")
            {created, skipped + 1}
        end
      end)

    IO.puts("  📊 建立: #{created_count} 個，略過: #{skipped_count} 個")
    IO.puts("")
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
