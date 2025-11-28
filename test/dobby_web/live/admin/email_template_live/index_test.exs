defmodule DobbyWeb.Admin.EmailTemplateLive.IndexTest do
  use DobbyWeb.LiveViewCase

  import Dobby.Fixtures, only: [email_template_fixture: 1]

  alias Dobby.Emails

  setup [:register_and_log_in_admin]

  describe "index listing" do
    test "lists email templates", %{conn: conn} do
      template = email_template_fixture(%{name: "Welcome Template"})

      {:ok, _view, html} = live(conn, ~p"/admin/email-templates")

      assert html =~ "郵件模板"
      assert html =~ template.name
    end

    test "filters templates via search", %{conn: conn} do
      email_template_fixture(%{name: "Alpha Template"})
      email_template_fixture(%{name: "Beta Template"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-templates")

      view
      |> element("form[phx-change='search']")
      |> render_change(%{"search" => "Alpha"})

      html = render(view)

      assert html =~ "Alpha Template"
      refute html =~ "Beta Template"
    end
  end

  describe "new/edit form" do
    test "renders new template form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/email-templates/new")

      assert html =~ "新增郵件模板"
      assert html =~ "HTML 內容"
    end

    test "validates presence of required fields", %{conn: conn} do
      before_total = Emails.list_global_templates(%{}).total
      {:ok, view, _html} = live(conn, ~p"/admin/email-templates/new")

      view
      |> form("form",
        email_template: %{
          "name" => "",
          "subject" => ""
        }
      )
      |> render_submit()

      assert Emails.list_global_templates(%{}).total == before_total
    end

    test "creates template and redirects", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/email-templates/new")

      view
      |> form("form",
        email_template: %{
          "name" => "Congrats",
          "subject" => "Congrats Subject",
          "text_content" => "Congrats"
        }
      )
      |> render_submit()

      assert_redirect(view, ~p"/admin/email-templates")
      assert %{items: items} = Emails.list_global_templates(%{search: "Congrats"})
      assert Enum.any?(items, &(&1.name == "Congrats"))
    end
  end

  describe "delete" do
    test "removes template from list", %{conn: conn} do
      template = email_template_fixture(%{name: "Disposable"})

      {:ok, view, _html} = live(conn, ~p"/admin/email-templates")

      view
      |> element("button[phx-click='delete_template'][phx-value-id='#{template.id}']")
      |> render_click()

      refute has_element?(view, "#email-template-#{template.id}")
    end
  end
end
