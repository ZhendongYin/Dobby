defmodule Dobby.EmailsTest do
  use Dobby.DataCase, async: true

  alias Dobby.{Accounts, Emails}
  alias Dobby.Fixtures

  setup do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "emails_test#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Emails Tester #{unique}"
      })

    %{admin: admin}
  end

  describe "set_campaign_template_default/2" do
    test "assigns default when association does not exist", %{admin: admin} do
      template = Fixtures.email_template_fixture()
      campaign = Fixtures.campaign_fixture(admin)

      assert {:ok, _} = Emails.set_campaign_template_default(campaign.id, template.id)
      assert Emails.get_default_email_template(campaign.id).id == template.id
    end

    test "switches default to the provided template", %{admin: admin} do
      template_a = Fixtures.email_template_fixture()
      template_b = Fixtures.email_template_fixture()
      campaign = Fixtures.campaign_fixture(admin)

      {:ok, _} = Emails.set_campaign_template_default(campaign.id, template_a.id)
      assert {:ok, _} = Emails.set_campaign_template_default(campaign.id, template_b.id)
      assert Emails.get_default_email_template(campaign.id).id == template_b.id
    end
  end

  describe "get_campaign_email_template/1" do
    test "falls back to first assignment when no default is set", %{admin: admin} do
      template = Fixtures.email_template_fixture()
      campaign = Fixtures.campaign_fixture(admin)

      {:ok, _assignment} = Emails.assign_template_to_campaign(campaign, template.id)

      assert Emails.get_campaign_email_template(campaign).id == template.id
    end
  end
end
