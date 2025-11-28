defmodule Dobby.CampaignsTest do
  use Dobby.DataCase, async: true

  alias Dobby.{Accounts, Campaigns}
  alias Dobby.Fixtures

  setup do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "campaign_ctx#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Context Admin #{unique}"
      })

    %{admin: admin}
  end

  describe "create_campaign/1 with default template" do
    test "assigns default email template when id provided", %{admin: admin} do
      template = Fixtures.email_template_fixture()

      attrs =
        base_attrs(admin)
        |> Map.put("default_template_id", template.id)

      assert {:ok, campaign} = Campaigns.create_campaign(attrs)

      assignment = Dobby.Emails.get_default_email_template(campaign.id)
      assert assignment.id == template.id
    end
  end

  describe "update_campaign/3 with default template" do
    test "updates default template when template id changes", %{admin: admin} do
      template_a = Fixtures.email_template_fixture()
      template_b = Fixtures.email_template_fixture()
      attrs = base_attrs(admin)

      {:ok, campaign} = Campaigns.create_campaign(attrs)
      {:ok, _} = Dobby.Emails.set_campaign_template_default(campaign.id, template_a.id)

      assert {:ok, campaign} =
               Campaigns.update_campaign(campaign, %{"default_template_id" => template_b.id})

      assignment = Dobby.Emails.get_default_email_template(campaign.id)
      assert assignment.id == template_b.id
    end
  end

  describe "authorization" do
    test "list_campaigns only returns campaigns for the specified admin", %{admin: admin} do
      # Create another admin
      {:ok, other_admin} =
        Accounts.register_admin(%{
          email: "other_admin#{System.unique_integer([:positive])}@example.com",
          password: "OtherAdm1nPass!",
          name: "Other Admin"
        })

      # Create campaigns for both admins
      {:ok, own_campaign} = Campaigns.create_campaign(base_attrs(admin))
      {:ok, _other_campaign} = Campaigns.create_campaign(base_attrs(other_admin))

      # List campaigns for admin
      result = Campaigns.list_campaigns(%{admin_id: admin.id})

      # Should only see own campaign
      assert result.total == 1
      assert Enum.any?(result.items, fn c -> c.id == own_campaign.id end)
      refute Enum.any?(result.items, fn c -> c.admin_id == other_admin.id end)
    end

    test "get_campaign_for_admin! returns campaign when admin owns it", %{admin: admin} do
      {:ok, campaign} = Campaigns.create_campaign(base_attrs(admin))

      result = Campaigns.get_campaign_for_admin!(campaign.id, admin.id)
      assert result.id == campaign.id
      assert result.admin_id == admin.id
    end

    test "get_campaign_for_admin! raises error when admin does not own campaign", %{admin: admin} do
      # Create another admin
      {:ok, other_admin} =
        Accounts.register_admin(%{
          email: "other_admin#{System.unique_integer([:positive])}@example.com",
          password: "OtherAdm1nPass!",
          name: "Other Admin"
        })

      {:ok, other_campaign} = Campaigns.create_campaign(base_attrs(other_admin))

      assert_raise Ecto.NoResultsError, fn ->
        Campaigns.get_campaign_for_admin!(other_campaign.id, admin.id)
      end
    end

    test "verify_campaign_ownership returns true when admin owns campaign", %{admin: admin} do
      {:ok, campaign} = Campaigns.create_campaign(base_attrs(admin))

      assert Campaigns.verify_campaign_ownership(campaign.id, admin.id) == true
    end

    test "verify_campaign_ownership returns false when admin does not own campaign", %{
      admin: admin
    } do
      # Create another admin
      {:ok, other_admin} =
        Accounts.register_admin(%{
          email: "other_admin#{System.unique_integer([:positive])}@example.com",
          password: "OtherAdm1nPass!",
          name: "Other Admin"
        })

      {:ok, other_campaign} = Campaigns.create_campaign(base_attrs(other_admin))

      assert Campaigns.verify_campaign_ownership(other_campaign.id, admin.id) == false
    end

    test "verify_prize_ownership returns true when admin owns prize's campaign", %{admin: admin} do
      {:ok, campaign} = Campaigns.create_campaign(base_attrs(admin))

      {:ok, prize} =
        Campaigns.create_prize(%{
          "name" => "Test Prize",
          "prize_type" => "physical",
          "campaign_id" => campaign.id,
          "probability_mode" => "percentage",
          "probability" => "10"
        })

      assert Campaigns.verify_prize_ownership(prize.id, admin.id) == true
    end

    test "verify_prize_ownership returns false when admin does not own prize's campaign", %{
      admin: admin
    } do
      # Create another admin
      {:ok, other_admin} =
        Accounts.register_admin(%{
          email: "other_admin#{System.unique_integer([:positive])}@example.com",
          password: "OtherAdm1nPass!",
          name: "Other Admin"
        })

      {:ok, other_campaign} = Campaigns.create_campaign(base_attrs(other_admin))

      {:ok, other_prize} =
        Campaigns.create_prize(%{
          "name" => "Other Prize",
          "prize_type" => "physical",
          "campaign_id" => other_campaign.id,
          "probability_mode" => "percentage",
          "probability" => "10"
        })

      assert Campaigns.verify_prize_ownership(other_prize.id, admin.id) == false
    end
  end

  defp base_attrs(admin) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      "name" => "Ctx Campaign #{System.unique_integer([:positive])}",
      "description" => "Description",
      "status" => "draft",
      "starts_at" => DateTime.add(now, 3600, :second),
      "ends_at" => DateTime.add(now, 7200, :second),
      "admin_id" => admin.id,
      "enable_protection" => false,
      "protection_count" => 0
    }
  end
end
