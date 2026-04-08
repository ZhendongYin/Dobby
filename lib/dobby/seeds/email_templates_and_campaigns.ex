defmodule Dobby.Seeds.EmailTemplatesAndCampaigns do
  @moduledoc false

  import Ecto.Query

  alias Dobby.{Accounts, Campaigns, Emails, Repo}
  alias Dobby.Campaigns.{Campaign, Prize}
  alias Dobby.Emails.EmailTemplate
  alias Dobby.PrizeLibrary.PrizeTemplate

  @admin_email "admin@dobby.com"

  @doc """
  Idempotent seed: email templates + sample campaigns (30 days from now).
  Requires an admin with `admin_email`; skips gracefully if missing.
  """
  def run(admin_email \\ @admin_email) do
    case Accounts.get_admin_by_email(admin_email) do
      nil ->
        IO.puts("⚠️  略過郵件模板與活動：找不到管理員 #{admin_email}，請先建立管理員。")

      admin ->
        do_run(admin)
    end
  end

  defp do_run(admin) do
    IO.puts("📧 建立郵件模板...")

    email_templates =
      email_definitions()
      |> Enum.map(&ensure_email_template/1)
      |> Enum.reject(&is_nil/1)

    starts_at = DateTime.utc_now() |> DateTime.truncate(:second)
    ends_at = DateTime.add(starts_at, 30, :day)

    IO.puts("")
    IO.puts("🎯 建立活動（開始：#{Calendar.strftime(starts_at, "%Y-%m-%d %H:%M")} UTC，為期 30 天）...")

    case email_templates do
      [] ->
        IO.puts("  ⚠️  沒有可用的郵件模板，略過活動建立。")

      tpls ->
        default_tpl = hd(tpls)

        [
          %{
            unique_name: "春季幸運抽",
            description: "刮刮樂活動，為期 30 天。",
            template: default_tpl
          },
          %{
            unique_name: "會員感恩月",
            description: "會員專屬活動，為期 30 天。",
            template: Enum.at(tpls, 1) || default_tpl
          }
        ]
        |> Enum.each(&ensure_campaign(&1, admin, starts_at, ends_at))
    end

    IO.puts("")
  end

  defp ensure_email_template(defn) do
    case Repo.get_by(EmailTemplate, name: defn.unique_name) do
      %EmailTemplate{} = t ->
        IO.puts("  ℹ️  已存在: #{t.name}")
        t

      nil ->
        case Emails.create_email_template(%{
               name: defn.unique_name,
               subject: defn.subject,
               html_content: defn.html_content,
               text_content: defn.text_content
             }) do
          {:ok, t} ->
            IO.puts("  ✅ #{t.name}")
            t

          {:error, cs} ->
            IO.puts("  ❌ 建立失敗: #{defn.unique_name}")
            IO.inspect(cs.errors, label: "errors")
            nil
        end
    end
  end

  defp ensure_campaign(cdef, admin, starts_at, ends_at) do
    campaign_or_nil =
      case Repo.get_by(Campaign, name: cdef.unique_name) do
        %Campaign{} = c ->
          IO.puts("  ℹ️  已存在: #{c.name}")
          c

        nil ->
          attrs = %{
            "name" => cdef.unique_name,
            "description" => cdef.description,
            "status" => "active",
            "starts_at" => starts_at,
            "ends_at" => ends_at,
            "admin_id" => admin.id,
            "enable_protection" => false,
            "protection_count" => 0,
            "default_template_id" => cdef.template.id
          }

          case Campaigns.create_campaign(attrs) do
            {:ok, campaign} ->
              IO.puts("  ✅ #{campaign.name} → 預設郵件模板: #{cdef.template.name}")
              campaign

            {:error, cs} ->
              IO.puts("  ❌ 建立失敗: #{cdef.unique_name}")
              IO.inspect(cs.errors, label: "errors")
              nil
          end
      end

    case campaign_or_nil do
      %Campaign{} = campaign -> ensure_campaign_prizes(campaign)
      _ -> :ok
    end
  end

  defp ensure_campaign_prizes(campaign) do
    IO.puts("  🎁 同步獎品（由模板匯入）…")

    Enum.each(demo_prize_template_specs(), fn %{name: name, overrides: overrides} ->
      case Repo.get_by(PrizeTemplate, name: name) do
        nil ->
          IO.puts("    ⚠️  略過（無獎品模板）: #{name}")

        %PrizeTemplate{} = template ->
          prize_exists? =
            Repo.exists?(
              from p in Prize,
                where: p.campaign_id == ^campaign.id and p.source_template_id == ^template.id
            )

          if prize_exists? do
            IO.puts("    ℹ️  獎品已存在: #{name}")
          else
            case Campaigns.create_prize_from_template(template.id, campaign.id, overrides) do
              {:ok, _} ->
                IO.puts("    ✅ 獎品: #{name}")

              {:error, cs} ->
                IO.puts("    ❌ 獎品建立失敗: #{name}")
                IO.inspect(cs.errors, label: "errors")
            end
          end
      end
    end)
  end

  # 與 priv/repo/seeds.exs 中的模板名稱一致；機率加總為 100%（percentage 模式）
  defp demo_prize_template_specs do
    [
      %{
        name: "iPhone 15 Pro",
        overrides: %{
          "probability" => Decimal.new("0.5"),
          "display_order" => 0,
          "total_quantity" => 10,
          "remaining_quantity" => 10
        }
      },
      %{
        name: "iPad Air",
        overrides: %{
          "probability" => Decimal.new("1"),
          "display_order" => 1,
          "total_quantity" => 15,
          "remaining_quantity" => 15
        }
      },
      %{
        name: "AirPods Pro",
        overrides: %{
          "probability" => Decimal.new("1.5"),
          "display_order" => 2,
          "total_quantity" => 20,
          "remaining_quantity" => 20
        }
      },
      %{
        name: "100元優惠券",
        overrides: %{
          "probability" => Decimal.new("2"),
          "display_order" => 3,
          "total_quantity" => 200,
          "remaining_quantity" => 200,
          "prize_code" => "DEMO100"
        }
      },
      %{
        name: "50元優惠券",
        overrides: %{
          "probability" => Decimal.new("3"),
          "display_order" => 4,
          "total_quantity" => 400,
          "remaining_quantity" => 400,
          "prize_code" => "DEMO50"
        }
      },
      %{
        name: "20元優惠券",
        overrides: %{
          "probability" => Decimal.new("5"),
          "display_order" => 5,
          "total_quantity" => 800,
          "remaining_quantity" => 800,
          "prize_code" => "DEMO20"
        }
      },
      %{
        name: "10元優惠券",
        overrides: %{
          "probability" => Decimal.new("8"),
          "display_order" => 6,
          "total_quantity" => 1000,
          "remaining_quantity" => 1000,
          "prize_code" => "DEMO10"
        }
      },
      %{
        name: "謝謝參與",
        overrides: %{
          "probability" => Decimal.new("79"),
          "display_order" => 7,
          "total_quantity" => 0,
          "remaining_quantity" => 0
        }
      }
    ]
  end

  defp email_definitions do
    html_win = """
    <h2>親愛的 {{user_name}} 您好：</h2>
    <p>恭喜您在「{{campaign_name}}」活動中抽中 <strong>{{prize_name}}</strong>！</p>
    <p>{{prize_description}}</p>
    <p>{{redemption_guide}}</p>
    <p style="margin-top: 24px;">如有任何問題，歡迎來信 {{support_email}}。</p>
    <p>祝您一切順心，活動團隊敬上</p>
    """

    text_win =
      """
      親愛的 {{user_name}} 您好：

      恭喜您在 {{campaign_name}} 活動中抽中 {{prize_name}}！
      {{prize_description}}

      {{redemption_guide}}

      有問題可聯絡 {{support_email}}。

      活動團隊敬上
      """
      |> String.trim()

    html_thanks = """
    <h2>{{user_name}} 您好，</h2>
    <p>感謝您參與「{{campaign_name}}」。</p>
    <p>本次未獲得獎項，邀請您下次再試手氣。如有疑問請聯絡 {{support_email}}。</p>
    <p>活動團隊敬上</p>
    """

    text_thanks =
      """
      {{user_name}} 您好，

      感謝您參與 {{campaign_name}}。
      本次未獲得獎項，歡迎下次再參與。

      {{support_email}}
      活動團隊敬上
      """
      |> String.trim()

    [
      %{
        unique_name: "中獎通知",
        subject: "恭喜您在中獎活動中獲得獎品",
        html_content: html_win,
        text_content: text_win
      },
      %{
        unique_name: "參與感謝",
        subject: "感謝您參與活動",
        html_content: html_thanks,
        text_content: text_thanks
      }
    ]
  end
end
