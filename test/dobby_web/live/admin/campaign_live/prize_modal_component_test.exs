defmodule DobbyWeb.Admin.CampaignLive.PrizeModalComponentTest do
  use DobbyWeb.LiveViewCase

  alias Dobby.{Accounts, Campaigns, PrizeLibrary, Emails}
  alias Dobby.Campaigns.Prize
  import Phoenix.Component

  setup do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "prize_modal_admin#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Prize Modal Admin #{unique}"
      })

    # Create a test campaign
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        "name" => "Test Campaign #{unique}",
        "description" => "Test Description",
        "status" => "active",
        "starts_at" => DateTime.add(now, -3600, :second),
        "ends_at" => DateTime.add(now, 7200, :second),
        "admin_id" => admin.id,
        "enable_protection" => false,
        "protection_count" => 0
      })

    # Create prize templates for testing
    {:ok, template1} =
      PrizeLibrary.create_template(%{
        "name" => "Template 1",
        "description" => "Template Description",
        "prize_type" => "physical",
        "image_url" => "https://example.com/image.jpg"
      })

    {:ok, template2} =
      PrizeLibrary.create_template(%{
        "name" => "Template 2",
        "description" => "Another Template",
        "prize_type" => "virtual",
        "image_url" => "https://example.com/image2.jpg",
        "redemption_guide" => "Redeem guide"
      })

    # Get email template options
    email_templates_result = Emails.list_global_templates(%{page: 1, page_size: 10})
    email_template_options = email_templates_result.items

    %{
      admin: admin,
      campaign: campaign,
      templates: [template1, template2],
      email_template_options: email_template_options
    }
  end

  describe "render/1" do
    test "renders modal when open? is true", %{
      campaign: campaign,
      templates: templates,
      email_template_options: email_template_options
    } do
      prize_modal = %{
        open?: true,
        mode: "new",
        title: "新增獎品",
        prize: nil,
        form: to_form(Campaigns.change_prize(%Prize{campaign_id: campaign.id})),
        selected_template_id: nil,
        template_locked_fields: []
      }

      assigns = %{
        id: "test-prize-modal",
        campaign: campaign,
        prize_modal: prize_modal,
        prize_templates: templates,
        email_template_options: email_template_options,
        current_admin: %{id: 1}
      }

      html = render_component(DobbyWeb.Admin.CampaignLive.PrizeModalComponent, assigns)

      assert html =~ "Prize Editor"
      assert html =~ "新增獎品"
      assert html =~ "preview-prize-form"
      assert html =~ "快速套用模板"
      assert html =~ "modal-template-select"
    end

    test "renders container but not modal content when open? is false", %{
      campaign: campaign,
      templates: templates,
      email_template_options: email_template_options
    } do
      prize_modal = %{
        open?: false,
        mode: nil,
        title: nil,
        prize: nil,
        form: nil,
        selected_template_id: nil,
        template_locked_fields: []
      }

      assigns = %{
        id: "test-prize-modal",
        campaign: campaign,
        prize_modal: prize_modal,
        prize_templates: templates,
        email_template_options: email_template_options,
        current_admin: %{id: 1}
      }

      html = render_component(DobbyWeb.Admin.CampaignLive.PrizeModalComponent, assigns)

      # Component should always return a root container div
      assert html =~ "prize-modal-container"
      # Modal content should not be present when open? is false
      refute html =~ "Prize Editor"
      refute html =~ "preview-prize-form"
    end

    test "shows template selector for new mode", %{
      campaign: campaign,
      templates: templates,
      email_template_options: email_template_options
    } do
      prize_modal = %{
        open?: true,
        mode: "new",
        title: "新增獎品",
        prize: nil,
        form: to_form(Campaigns.change_prize(%Prize{campaign_id: campaign.id})),
        selected_template_id: nil,
        template_locked_fields: []
      }

      assigns = %{
        id: "test-prize-modal",
        campaign: campaign,
        prize_modal: prize_modal,
        prize_templates: templates,
        email_template_options: email_template_options,
        current_admin: %{id: 1}
      }

      html = render_component(DobbyWeb.Admin.CampaignLive.PrizeModalComponent, assigns)

      assert html =~ "快速套用模板"
      assert html =~ "modal-template-select"
    end

    test "hides template selector for edit mode", %{
      campaign: campaign,
      templates: templates,
      email_template_options: email_template_options
    } do
      prize = prize_fixture(campaign)

      prize_modal = %{
        open?: true,
        mode: "edit",
        title: "編輯獎品",
        prize: prize,
        form: to_form(Campaigns.change_prize(prize)),
        selected_template_id: nil,
        template_locked_fields: []
      }

      assigns = %{
        id: "test-prize-modal",
        campaign: campaign,
        prize_modal: prize_modal,
        prize_templates: templates,
        email_template_options: email_template_options,
        current_admin: %{id: 1}
      }

      html = render_component(DobbyWeb.Admin.CampaignLive.PrizeModalComponent, assigns)

      refute html =~ "快速套用模板"
      assert html =~ "編輯獎品"
    end

    test "shows virtual prize code field when prize_type is virtual", %{
      campaign: campaign,
      templates: templates,
      email_template_options: email_template_options
    } do
      changeset = Campaigns.change_prize(%Prize{campaign_id: campaign.id, prize_type: "virtual"})

      prize_modal = %{
        open?: true,
        mode: "new",
        title: "新增獎品",
        prize: %Prize{campaign_id: campaign.id, prize_type: "virtual"},
        form: to_form(changeset),
        selected_template_id: nil,
        template_locked_fields: []
      }

      assigns = %{
        id: "test-prize-modal",
        campaign: campaign,
        prize_modal: prize_modal,
        prize_templates: templates,
        email_template_options: email_template_options,
        current_admin: %{id: 1}
      }

      html = render_component(DobbyWeb.Admin.CampaignLive.PrizeModalComponent, assigns)

      assert html =~ "兌換碼"
      assert html =~ "prize_code"
    end

    test "shows protection checkbox when campaign has protection enabled", %{
      campaign: campaign,
      templates: templates,
      email_template_options: email_template_options
    } do
      # Update campaign to enable protection
      Campaigns.update_campaign(campaign, %{"enable_protection" => true})
      campaign = Campaigns.get_campaign!(campaign.id)

      prize_modal = %{
        open?: true,
        mode: "new",
        title: "新增獎品",
        prize: nil,
        form: to_form(Campaigns.change_prize(%Prize{campaign_id: campaign.id})),
        selected_template_id: nil,
        template_locked_fields: []
      }

      assigns = %{
        id: "test-prize-modal",
        campaign: campaign,
        prize_modal: prize_modal,
        prize_templates: templates,
        email_template_options: email_template_options,
        current_admin: %{id: 1}
      }

      html = render_component(DobbyWeb.Admin.CampaignLive.PrizeModalComponent, assigns)

      assert html =~ "設為保護獎項"
      assert html =~ "is_protected"
    end

    test "disables fields when they are in template_locked_fields", %{
      campaign: campaign,
      templates: templates,
      email_template_options: email_template_options
    } do
      prize_modal = %{
        open?: true,
        mode: "new",
        title: "新增獎品",
        prize: nil,
        form: to_form(Campaigns.change_prize(%Prize{campaign_id: campaign.id})),
        selected_template_id: "123",
        template_locked_fields: ["name", "description"]
      }

      assigns = %{
        id: "test-prize-modal",
        campaign: campaign,
        prize_modal: prize_modal,
        prize_templates: templates,
        email_template_options: email_template_options,
        current_admin: %{id: 1}
      }

      html = render_component(DobbyWeb.Admin.CampaignLive.PrizeModalComponent, assigns)

      # Check that disabled attribute is present for locked fields
      assert html =~ "disabled"
    end

    test "renders all form fields correctly", %{
      campaign: campaign,
      templates: templates,
      email_template_options: email_template_options
    } do
      prize_modal = %{
        open?: true,
        mode: "new",
        title: "新增獎品",
        prize: nil,
        form: to_form(Campaigns.change_prize(%Prize{campaign_id: campaign.id})),
        selected_template_id: nil,
        template_locked_fields: []
      }

      assigns = %{
        id: "test-prize-modal",
        campaign: campaign,
        prize_modal: prize_modal,
        prize_templates: templates,
        email_template_options: email_template_options,
        current_admin: %{id: 1}
      }

      html = render_component(DobbyWeb.Admin.CampaignLive.PrizeModalComponent, assigns)

      # Check that all required fields are present
      assert html =~ "獎品名稱"
      assert html =~ "獎品描述"
      assert html =~ "圖片 URL"
      assert html =~ "獎品類型"
      assert html =~ "中獎機率"
      assert html =~ "總數量"
      assert html =~ "剩餘數量"
      assert html =~ "每日上限"
      assert html =~ "排序"
      assert html =~ "郵件通知模板"
      assert html =~ "兌換說明"
    end
  end

  defp prize_fixture(campaign, attrs \\ %{}) do
    defaults = %{
      "name" => "Test Prize #{System.unique_integer([:positive])}",
      "description" => "Test Prize Description",
      "prize_type" => "physical",
      "campaign_id" => campaign.id,
      "total_quantity" => 10,
      "remaining_quantity" => 10,
      "probability_mode" => "percentage",
      "probability" => "50",
      "display_order" => 1
    }

    {:ok, prize} =
      defaults
      |> Map.merge(Dobby.Fixtures.stringify_keys(attrs))
      |> Campaigns.create_prize()

    prize
  end
end
