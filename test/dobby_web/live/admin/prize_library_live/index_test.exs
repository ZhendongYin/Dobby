defmodule DobbyWeb.Admin.PrizeLibraryLive.IndexTest do
  use DobbyWeb.LiveViewCase

  import Dobby.Fixtures, only: [prize_template_fixture: 1]

  alias Dobby.PrizeLibrary

  setup [:register_and_log_in_admin]

  describe "index listing" do
    test "lists existing templates", %{conn: conn} do
      template = prize_template_fixture(%{name: "Golden Ticket"})

      {:ok, _view, html} = live(conn, ~p"/admin/prize-library")

      assert html =~ "Prize Library"
      assert html =~ template.name
    end

    test "filters by search", %{conn: conn} do
      prize_template_fixture(%{name: "Alpha Template"})
      prize_template_fixture(%{name: "Beta Template"})

      {:ok, view, _html} = live(conn, ~p"/admin/prize-library")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "Alpha"})

      html = render(view)

      assert html =~ "Alpha Template"
      refute html =~ "Beta Template"
    end

    test "deletes a template", %{conn: conn} do
      template = prize_template_fixture(%{name: "To Be Deleted"})

      {:ok, view, _html} = live(conn, ~p"/admin/prize-library")

      view
      |> element("button[phx-click='delete-template'][phx-value-id='#{template.id}']")
      |> render_click()

      refute has_element?(view, "#prize-template-#{template.id}")
    end
  end

  describe "new template form" do
    test "renders form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/prize-library/new")

      assert html =~ "新增獎品模板"
      assert html =~ "獎品圖片"
    end

    test "validates errors when submitting invalid data", %{conn: conn} do
      before_total = PrizeLibrary.list_templates(%{}).total
      {:ok, view, _html} = live(conn, ~p"/admin/prize-library/new")

      view
      |> form("form",
        prize_template: %{
          "name" => "",
          "prize_type" => "physical"
        }
      )
      |> render_submit()

      assert PrizeLibrary.list_templates(%{}).total == before_total
    end

    test "creates template with valid data", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/prize-library/new")

      view
      |> form("form",
        prize_template: %{
          "name" => "New Template",
          "prize_type" => "physical",
          "description" => "Desc"
        }
      )
      |> render_submit()

      assert_redirect(view, ~p"/admin/prize-library")
      assert %{items: items} = PrizeLibrary.list_templates(%{search: "New Template"})
      assert Enum.any?(items, &(&1.name == "New Template"))
    end
  end
end
