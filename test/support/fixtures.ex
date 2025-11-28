defmodule Dobby.Fixtures do
  @moduledoc false

  alias Dobby.Campaigns
  alias Dobby.Emails
  alias Dobby.PrizeLibrary

  def campaign_fixture(admin, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    defaults = %{
      "name" => "Campaign #{System.unique_integer([:positive])}",
      "description" => "Description",
      "status" => "draft",
      "starts_at" => DateTime.add(now, 3600, :second),
      "ends_at" => DateTime.add(now, 7200, :second),
      "admin_id" => admin.id,
      "enable_protection" => false,
      "protection_count" => 0
    }

    attrs =
      defaults
      |> Map.merge(stringify_keys(attrs))

    {:ok, campaign} = Campaigns.create_campaign(attrs)
    campaign
  end

  def prize_template_fixture(attrs \\ %{}) do
    defaults = %{
      name: "Template #{System.unique_integer([:positive])}",
      prize_type: "physical",
      description: "Description",
      redemption_guide: "Guide"
    }

    {:ok, template} = PrizeLibrary.create_template(Map.merge(defaults, attrs))
    template
  end

  def email_template_fixture(attrs \\ %{}) do
    defaults = %{
      name: "Email Template #{System.unique_integer([:positive])}",
      subject: "Subject #{System.unique_integer([:positive])}",
      html_content: "<p>Hello</p>",
      text_content: "Hello"
    }

    {:ok, template} = Emails.create_email_template(Map.merge(defaults, attrs))
    template
  end

  def stringify_keys(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end
end
