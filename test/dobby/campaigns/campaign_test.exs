defmodule Dobby.Campaigns.CampaignTest do
  use Dobby.DataCase, async: true

  alias Dobby.Campaigns.Campaign
  alias Dobby.Accounts

  setup do
    unique = System.unique_integer([:positive])

    {:ok, admin} =
      Accounts.register_admin(%{
        email: "campaign_tester#{unique}@example.com",
        password: "Adm1nPass!#{unique}",
        name: "Campaign Tester #{unique}"
      })

    %{admin: admin}
  end

  describe "changeset/2" do
    test "is valid with required attributes", %{admin: admin} do
      attrs = valid_attrs(admin)

      changeset = Campaign.changeset(%Campaign{}, attrs)

      assert changeset.valid?
    end

    test "requires mandatory fields", %{admin: admin} do
      attrs =
        valid_attrs(admin)
        |> Map.drop([:name, :starts_at])

      changeset = Campaign.changeset(%Campaign{}, attrs)

      errors = errors_on(changeset)

      assert "此欄位為必填" in Map.get(errors, :name, [])
      assert "此欄位為必填" in Map.get(errors, :starts_at, [])
    end

    test "validates date range ordering", %{admin: admin} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs =
        valid_attrs(admin)
        |> Map.put(:starts_at, DateTime.add(now, 7200, :second))
        |> Map.put(:ends_at, DateTime.add(now, 3600, :second))

      changeset = Campaign.changeset(%Campaign{}, attrs)

      assert "結束時間必須晚於開始時間" in Map.get(errors_on(changeset), :ends_at, [])
    end
  end

  defp valid_attrs(admin) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      name: "Campaign #{System.unique_integer([:positive])}",
      description: "Description",
      status: "draft",
      starts_at: DateTime.add(now, 3600, :second),
      ends_at: DateTime.add(now, 7200, :second),
      background_image_url: "https://example.com/bg.png",
      theme_color: "#FFFFFF",
      no_prize_message: "Try again!",
      rules_text: "Follow rules.",
      enable_protection: false,
      protection_count: 0,
      admin_id: admin.id
    }
  end
end
