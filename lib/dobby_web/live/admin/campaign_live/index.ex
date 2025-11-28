defmodule DobbyWeb.Admin.CampaignLive.Index do
  use DobbyWeb, :live_view

  alias Dobby.Campaigns
  alias Dobby.Campaigns.Campaign
  alias Dobby.Campaigns.Prize
  alias Dobby.PrizeLibrary
  alias Dobby.Statistics
  alias Dobby.Emails
  alias Dobby.Lottery
  alias DobbyWeb.Admin.CampaignLive.PrizeModalComponent
  alias Decimal
  alias DobbyWeb.LiveViewHelpers

  @default_prize_filter %{search: "", type: "all"}
  @preview_tabs ~w(overview prizes winners activity)
  @default_preview_tab "overview"
  @winners_preview_limit 25
  @default_winner_filter %{status: "all", search: ""}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:status_filter, "all")
     |> assign(:page, 1)
     |> assign(:page_size, 20)
     |> assign(:sort_by, "inserted_at")
     |> assign(:sort_order, "desc")
     |> assign(:campaign, nil)
     |> assign(:form, nil)
     |> assign(:active_tab, @default_preview_tab)
     |> assign(:email_template_options, [])
     |> assign(:latest_background_image_url, nil)
     |> load_campaigns()}
  end

  @impl true
  def handle_params(params, _url, %{assigns: %{live_action: :preview}} = socket) do
    id = params["id"]
    tab = normalize_preview_tab(Map.get(params, "tab"))

    winners_page =
      LiveViewHelpers.parse_integer(
        params["winners_page"],
        socket.assigns[:winning_records_page] || 1
      )

    winners_page_size =
      LiveViewHelpers.parse_integer(
        params["winners_page_size"],
        socket.assigns[:winning_records_page_size] || @winners_preview_limit
      )

    winners_sort_by =
      params["winners_sort_by"] || socket.assigns[:winning_records_sort_by] || "inserted_at"

    winners_sort_order =
      params["winners_sort_order"] || socket.assigns[:winning_records_sort_order] || "desc"

    force_reload? = params["reload"] in ["1", "true"]

    socket =
      cond do
        force_reload? ->
          apply_action(socket, :preview, Map.put(params, "tab", tab))

        preview_loaded?(socket, id) ->
          # If preview is already loaded, check if pagination/sort params changed
          current_page = socket.assigns[:winning_records_page] || 1
          current_page_size = socket.assigns[:winning_records_page_size] || @winners_preview_limit
          current_tab = socket.assigns[:active_tab] || @default_preview_tab
          current_sort_by = socket.assigns[:winning_records_sort_by] || "inserted_at"
          current_sort_order = socket.assigns[:winning_records_sort_order] || "desc"

          if winners_page != current_page || winners_page_size != current_page_size ||
               tab != current_tab || winners_sort_by != current_sort_by ||
               winners_sort_order != current_sort_order do
            # Reload with new pagination/sort params
            socket
            |> assign(:active_tab, tab)
            |> assign(:winning_records_page, winners_page)
            |> assign(:winning_records_page_size, winners_page_size)
            |> assign(:winning_records_sort_by, winners_sort_by)
            |> assign(:winning_records_sort_order, winners_sort_order)
            |> then(fn s ->
              winner_filter = s.assigns[:winner_filter] || @default_winner_filter
              reload_winning_records(s, winner_filter)
            end)
          else
            socket
            |> assign(:active_tab, tab)
          end

        true ->
          apply_action(socket, :preview, Map.put(params, "tab", tab))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    require Logger

    Logger.debug(
      "handle_params: live_action = #{socket.assigns.live_action}, params = #{inspect(params)}"
    )

    socket = apply_action(socket, socket.assigns.live_action, params)

    Logger.debug(
      "handle_params: after apply_action, @uploads = #{inspect(socket.assigns[:uploads])}"
    )

    {:noreply, socket}
  end

  defp apply_action(socket, :index, params) do
    page = parse_integer(params["page"], socket.assigns[:page] || 1)
    page_size = parse_integer(params["page_size"], socket.assigns[:page_size] || 20)
    search = params["search"] || socket.assigns[:search] || ""
    status = params["status"] || socket.assigns[:status_filter] || "all"
    sort_by = params["sort_by"] || socket.assigns[:sort_by] || "inserted_at"
    sort_order = params["sort_order"] || socket.assigns[:sort_order] || "desc"

    socket
    |> assign(:page_title, "Campaigns")
    |> assign(:campaign, nil)
    |> assign(:form, nil)
    |> assign(:page, page)
    |> assign(:page_size, page_size)
    |> assign(:search, search)
    |> assign(:status_filter, status)
    |> assign(:sort_by, sort_by)
    |> assign(:sort_order, sort_order)
    |> load_campaigns()
  end

  defp apply_action(socket, :new, _params) do
    changeset = Campaigns.change_campaign(%Campaign{})
    form = to_form(changeset)

    socket
    |> assign(:page_title, "New Campaign")
    |> assign(:campaign, %Campaign{})
    |> assign(:form, form)
    |> assign(:latest_background_image_url, nil)
    |> allow_upload(:background_image,
      accept: ~w(.jpg .jpeg .png .gif .webp),
      max_entries: 1,
      max_file_size: 10_000_000,
      auto_upload: true
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    admin_id = socket.assigns.current_admin.id
    campaign = Campaigns.get_campaign_for_admin!(id, admin_id)
    changeset = Campaigns.change_campaign(campaign)
    form = to_form(changeset)

    socket
    |> assign(:page_title, "Edit Campaign")
    |> assign(:campaign, campaign)
    |> assign(:form, form)
    |> assign(:latest_background_image_url, campaign.background_image_url)
    |> allow_upload(:background_image,
      accept: ~w(.jpg .jpeg .png .gif .webp),
      max_entries: 1,
      max_file_size: 10_000_000,
      auto_upload: true
    )
  end

  defp apply_action(socket, :preview, %{"id" => id} = params) do
    tab = normalize_preview_tab(Map.get(params, "tab"))
    winners_page = LiveViewHelpers.parse_integer(params["winners_page"], 1)

    winners_page_size =
      LiveViewHelpers.parse_integer(params["winners_page_size"], @winners_preview_limit)

    winners_sort_by = Map.get(params, "winners_sort_by", "inserted_at")
    winners_sort_order = Map.get(params, "winners_sort_order", "desc")

    load_preview(socket, id, tab,
      winners_page: winners_page,
      winners_page_size: winners_page_size,
      winners_sort_by: winners_sort_by,
      winners_sort_order: winners_sort_order
    )
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = normalize_preview_tab(tab)

    socket =
      case socket.assigns do
        %{live_action: :preview, campaign: %Campaign{id: campaign_id}} ->
          push_patch(socket, to: ~p"/admin/campaigns/#{campaign_id}/preview?#{[tab: tab]}")

        _ ->
          socket
      end

    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("open_preview", %{"id" => id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/campaigns/#{id}/preview")}
  end

  @impl true
  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    page_size = LiveViewHelpers.parse_integer(page_size, 20)

    {:noreply,
     socket
     |> assign(:page_size, page_size)
     |> assign(:page, 1)
     |> load_campaigns()
     |> push_patch(to: build_pagination_path(socket, 1, page_size))}
  end

  @impl true
  def handle_event("go_to_page", %{"page" => page}, socket) do
    page = LiveViewHelpers.parse_integer(page, 1)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_campaigns()
     |> push_patch(to: build_pagination_path(socket, page, socket.assigns.page_size))}
  end

  @impl true
  def handle_event("sort", %{"field" => field, "order" => order}, socket) do
    {:noreply,
     socket
     |> assign(:sort_by, field)
     |> assign(:sort_order, order)
     |> assign(:page, 1)
     |> load_campaigns()
     |> push_patch(to: build_pagination_path(socket, 1, socket.assigns.page_size, field, order))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    campaign = Campaigns.get_campaign!(id)
    {:ok, _} = Campaigns.delete_campaign(campaign)

    {:noreply,
     socket
     |> assign(:page, 1)
     |> load_campaigns()}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:page, 1)
     |> load_campaigns()}
  end

  @impl true
  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, status)
     |> assign(:page, 1)
     |> load_campaigns()}
  end

  @impl true
  def handle_event("toggle_status", %{"id" => id}, socket) do
    admin_id = socket.assigns.current_admin.id
    campaign = Campaigns.get_campaign_for_admin!(id, admin_id)
    new_status = if campaign.status == "active", do: "disabled", else: "active"

    {:ok, _} = Campaigns.update_campaign(campaign, %{status: new_status}, admin_id: admin_id)

    {:noreply,
     socket
     |> load_campaigns()}
  end

  @impl true
  def handle_event("open_prize_modal", %{"mode" => mode} = params, socket) do
    campaign = socket.assigns.campaign

    {prize, title, locked_fields} =
      case mode do
        "edit" ->
          admin_id = socket.assigns.current_admin.id
          prize = Campaigns.get_prize!(params["prize_id"])
          # Verify ownership before allowing edit
          unless Campaigns.verify_prize_ownership(prize.id, admin_id) do
            raise Ecto.NoResultsError, queryable: Dobby.Campaigns.Prize
          end

          # 如果奖品有 source_template_id，锁定模板字段
          locked_fields =
            if prize.source_template_id do
              ["name", "description", "image_url", "prize_type", "redemption_guide"]
            else
              []
            end

          {prize, "編輯獎品 · #{prize_name(prize)}", locked_fields}

        _ ->
          {%Prize{campaign_id: campaign.id}, "新增獎品", []}
      end

    changeset = Campaigns.change_prize(prize)

    {:noreply,
     socket
     |> set_prize_modal(%{
       open?: true,
       mode: mode,
       title: title,
       prize: prize,
       form: to_form(changeset),
       selected_template_id: prize.source_template_id,
       template_locked_fields: locked_fields
     })}
  end

  @impl true
  def handle_event("close_prize_modal", _params, socket) do
    {:noreply, assign(socket, :prize_modal, default_prize_modal())}
  end

  @impl true
  def handle_event("prize_filter", %{"filter" => filter_params}, socket) do
    prizes = socket.assigns[:prizes] || []
    {:noreply, assign_preview_prize_data(socket, prizes, filter_params)}
  end

  @impl true
  def handle_event("load_prize_template", %{"template_id" => ""}, socket) do
    modal = socket.assigns.prize_modal
    prize = modal.prize || %Prize{campaign_id: socket.assigns.campaign.id}
    changeset = Campaigns.change_prize(prize, %{})

    {:noreply,
     set_prize_modal(socket, %{
       selected_template_id: nil,
       form: to_form(changeset),
       template_locked_fields: []
     })}
  end

  @impl true
  def handle_event("load_prize_template", %{"template_id" => template_id}, socket) do
    modal = socket.assigns.prize_modal
    prize = modal.prize || %Prize{campaign_id: socket.assigns.campaign.id}

    template =
      template_id
      |> PrizeLibrary.get_template!()

    # 先创建 changeset（不包含 source_template_id），这样字段值能够进入 changeset
    form_attrs = %{
      "name" => template.name,
      "description" => template.description,
      "image_url" => template.image_url,
      "prize_type" => template.prize_type,
      "redemption_guide" => template.redemption_guide
    }

    changeset =
      prize
      |> Campaigns.change_prize(form_attrs)
      # 使用 put_change 设置 source_template_id 和字段值
      # 这样字段值会出现在 changeset 中用于表单显示，但保存时会被移除
      |> Ecto.Changeset.put_change(:source_template_id, template.id)
      |> Ecto.Changeset.put_change(:name, template.name)
      |> Ecto.Changeset.put_change(:description, template.description)
      |> Ecto.Changeset.put_change(:image_url, template.image_url)
      |> Ecto.Changeset.put_change(:prize_type, template.prize_type)
      |> Ecto.Changeset.put_change(:redemption_guide, template.redemption_guide)

    # 更新 prize 对象以反映模板数据（用于条件判断）
    updated_prize = %{
      prize
      | name: template.name,
        description: template.description,
        image_url: template.image_url,
        prize_type: template.prize_type,
        redemption_guide: template.redemption_guide,
        source_template_id: template.id
    }

    # 锁定模板带入的字段
    locked_fields = ["name", "description", "image_url", "prize_type", "redemption_guide"]

    {:noreply,
     set_prize_modal(socket, %{
       form: to_form(changeset),
       prize: updated_prize,
       selected_template_id: template_id,
       template_locked_fields: locked_fields
     })}
  end

  @impl true
  def handle_event("validate_prize_modal", %{"prize" => prize_params}, socket) do
    modal = socket.assigns.prize_modal
    prize = modal.prize || %Prize{campaign_id: socket.assigns.campaign.id}

    changeset =
      prize
      |> Campaigns.change_prize(prize_params)
      |> Map.put(:action, :validate)

    # 更新 prize 对象以反映表单变化（特别是 prize_type）
    updated_prize =
      if prize_params["prize_type"] do
        %{prize | prize_type: prize_params["prize_type"]}
      else
        prize
      end

    {:noreply,
     set_prize_modal(socket, %{
       form: to_form(changeset),
       prize: updated_prize
     })}
  end

  @impl true
  def handle_event("save_prize_modal", %{"prize" => prize_params}, socket) do
    payload = build_prize_modal_payload(socket, prize_params)
    process_prize_modal_save(socket, payload)
  end

  # Preview operations handlers
  @impl true
  def handle_event(
        "quick_adjust_quantity",
        %{"prize_id" => prize_id, "quantity" => quantity},
        socket
      ) do
    prize = Campaigns.get_prize!(prize_id)

    quantity_value =
      cond do
        quantity in ["", nil] ->
          nil

        true ->
          case Integer.parse(quantity) do
            {num, _} -> num
            :error -> prize.remaining_quantity
          end
      end

    admin_id = socket.assigns.current_admin.id

    case Campaigns.update_prize(prize, %{remaining_quantity: quantity_value}, admin_id: admin_id) do
      {:ok, _} ->
        prizes = Campaigns.list_prizes(socket.assigns.campaign.id)

        socket =
          socket
          |> assign_preview_prize_data(prizes)
          |> put_flash(:info, "獎品庫存已更新")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "更新失敗")}
    end
  end

  @impl true
  def handle_event("import_prize_template", %{"template_id" => template_id}, socket) do
    case Campaigns.create_prize_from_template(template_id, socket.assigns.campaign.id, %{}) do
      {:ok, _} ->
        prizes = Campaigns.list_prizes(socket.assigns.campaign.id)

        socket =
          socket
          |> assign_preview_prize_data(prizes)
          |> put_flash(:info, "獎品已匯入")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "匯入失敗")}
    end
  end

  @impl true
  def handle_event(
        "bulk_update_prize_status",
        %{"prize_ids" => prize_ids, "action" => action},
        socket
      ) do
    # Handle bulk operations like enable/disable protection
    prize_ids_list = String.split(prize_ids, ",")

    admin_id = socket.assigns.current_admin.id

    Enum.each(prize_ids_list, fn id ->
      prize = Campaigns.get_prize!(id)

      # Verify ownership before updating
      if Campaigns.verify_prize_ownership(prize.id, admin_id) do
        attrs =
          case action do
            "protect" -> %{is_protected: true}
            "unprotect" -> %{is_protected: false}
            _ -> %{}
          end

        Campaigns.update_prize(prize, attrs, admin_id: admin_id)
      end
    end)

    prizes = Campaigns.list_prizes(socket.assigns.campaign.id)

    socket =
      socket
      |> assign_preview_prize_data(prizes)
      |> put_flash(:info, "批量操作完成")

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_prize", %{"id" => id}, socket) do
    admin_id = socket.assigns.current_admin.id
    prize = Campaigns.get_prize!(id)

    # Verify ownership before deleting
    if Campaigns.verify_prize_ownership(prize.id, admin_id) do
      {:ok, _} = Campaigns.delete_prize(prize, admin_id: admin_id)
      prizes = Campaigns.list_prizes(socket.assigns.campaign.id)

      socket =
        socket
        |> assign_preview_prize_data(prizes)
        |> put_flash(:info, "獎品已刪除")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "無權限刪除此獎品")}
    end
  end

  @impl true
  def handle_event("toggle_prize_protection", %{"id" => id}, socket) do
    admin_id = socket.assigns.current_admin.id
    prize = Campaigns.get_prize!(id)

    # Verify ownership before updating
    if Campaigns.verify_prize_ownership(prize.id, admin_id) do
      {:ok, _} =
        Campaigns.update_prize(prize, %{is_protected: !prize.is_protected}, admin_id: admin_id)

      prizes = Campaigns.list_prizes(socket.assigns.campaign.id)

      socket =
        socket
        |> assign_preview_prize_data(prizes)
        |> put_flash(:info, "保護設定已更新")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "無權限修改此獎品")}
    end
  end

  @impl true
  def handle_event("export_winners_csv", _params, socket) do
    campaign = socket.assigns.campaign
    winner_filter = socket.assigns[:winner_filter] || @default_winner_filter

    # CSV export should not be paginated - fetch all records
    opts = %{
      page: 1,
      # Large number to get all records
      page_size: 999_999,
      status: if(winner_filter.status == "all", do: nil, else: winner_filter.status),
      search: if(winner_filter.search == "", do: nil, else: winner_filter.search),
      sort_by: socket.assigns[:winning_records_sort_by] || "inserted_at",
      sort_order: socket.assigns[:winning_records_sort_order] || "desc"
    }

    result = Lottery.list_winning_records(campaign.id, opts)
    # Extract items from paginated result
    records = result.items
    csv = build_winners_csv(records)

    {:noreply,
     push_event(socket, "download_csv", %{
       content: csv,
       filename: "campaign-#{campaign.id}-winners.csv",
       content_type: "text/csv; charset=utf-8"
     })}
  end

  @impl true
  def handle_event("filter_winners", %{"status" => status}, socket) do
    winner_filter =
      Map.put(socket.assigns[:winner_filter] || @default_winner_filter, :status, status)

    {:noreply, reload_winning_records(socket, winner_filter)}
  end

  @impl true
  def handle_event("search_winners", %{"search" => search}, socket) do
    winner_filter =
      Map.put(socket.assigns[:winner_filter] || @default_winner_filter, :search, search)

    {:noreply, reload_winning_records(socket, winner_filter)}
  end

  @impl true
  def handle_event("mark_winner_status", %{"id" => id, "status" => status}, socket) do
    record = Enum.find(socket.assigns.winning_records, &(&1.id == id))

    case Lottery.update_winning_record_status(record, status) do
      {:ok, _} ->
        winner_filter = socket.assigns[:winner_filter] || @default_winner_filter

        socket =
          reload_winning_records(socket, winner_filter)
          |> put_flash(:info, "狀態已更新")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "更新失敗")}
    end
  end

  @impl true
  def handle_event("resend_winner_email", %{"id" => id}, socket) do
    record = Enum.find(socket.assigns.winning_records, &(&1.id == id))

    if record && record.email do
      Task.start(fn ->
        case Emails.resend_winning_notification(record) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            require Logger
            Logger.error("Failed to resend email: #{inspect(reason)}")
        end
      end)

      winner_filter = socket.assigns[:winner_filter] || @default_winner_filter

      socket =
        reload_winning_records(socket, winner_filter)
        |> put_flash(:info, "郵件已重新發送")

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "記錄不存在或缺少郵件地址")}
    end
  end

  @impl true
  def handle_event("go_to_winners_page", %{"page" => page}, socket) do
    page = LiveViewHelpers.parse_integer(page, 1)
    winner_filter = socket.assigns[:winner_filter] || @default_winner_filter

    socket =
      socket
      |> assign(:winning_records_page, page)

    socket = reload_winning_records(socket, winner_filter)

    {:noreply, push_patch(socket, to: build_winners_pagination_path(socket, page, nil))}
  end

  @impl true
  def handle_event("change_winners_page_size", %{"winners_page_size" => page_size}, socket) do
    page_size = LiveViewHelpers.parse_integer(page_size, @winners_preview_limit)
    winner_filter = socket.assigns[:winner_filter] || @default_winner_filter

    socket =
      socket
      |> assign(:winning_records_page_size, page_size)
      # Reset to first page
      |> assign(:winning_records_page, 1)

    socket = reload_winning_records(socket, winner_filter)

    {:noreply, push_patch(socket, to: build_winners_pagination_path(socket, 1, page_size))}
  end

  @impl true
  def handle_event("sort_winners", %{"field" => field}, socket) do
    current_sort_by = socket.assigns[:winning_records_sort_by] || "inserted_at"
    current_sort_order = socket.assigns[:winning_records_sort_order] || "desc"
    winner_filter = socket.assigns[:winner_filter] || @default_winner_filter

    # Toggle sort order if clicking the same field, otherwise use desc
    {new_sort_by, new_sort_order} =
      if current_sort_by == field do
        {field, if(current_sort_order == "desc", do: "asc", else: "desc")}
      else
        {field, "desc"}
      end

    socket =
      socket
      |> assign(:winning_records_sort_by, new_sort_by)
      |> assign(:winning_records_sort_order, new_sort_order)
      # Reset to first page when sorting
      |> assign(:winning_records_page, 1)

    socket = reload_winning_records(socket, winner_filter)

    {:noreply, push_patch(socket, to: build_winners_pagination_path(socket, 1, nil))}
  end

  @impl true
  def handle_event("refresh_preview", _params, socket) do
    %{campaign: %Campaign{id: campaign_id}, active_tab: tab} = socket.assigns

    socket =
      load_preview(
        socket,
        campaign_id,
        tab,
        prize_filter: socket.assigns[:prize_filter] || @default_prize_filter,
        winner_filter: socket.assigns[:winner_filter] || @default_winner_filter,
        winners_page: socket.assigns[:winning_records_page] || 1,
        winners_page_size: socket.assigns[:winning_records_page_size] || @winners_preview_limit,
        winners_sort_by: socket.assigns[:winning_records_sort_by] || "inserted_at",
        winners_sort_order: socket.assigns[:winning_records_sort_order] || "desc"
      )
      |> put_flash(:info, "資料已更新")

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"campaign" => campaign_params} = params, socket) do
    require Logger

    # Check if this validate event contains upload data
    # If it does, we need to handle it carefully to avoid component errors
    has_uploads = Map.has_key?(params, "uploads")

    if has_uploads do
      Logger.debug(
        "handle_event validate: Contains upload data, skipping component update to avoid upload errors"
      )

      # When upload data is present, just update the form without updating the component
      # The upload will be handled via handle_progress, which will then update the component
      campaign_params = Map.drop(campaign_params, ["_target"])
      {default_template_id, campaign_params} = Map.pop(campaign_params, "default_template_id")
      campaign_params = normalize_datetime_params(campaign_params)

      changeset =
        socket.assigns.campaign
        |> Campaigns.change_campaign(campaign_params)
        |> Map.put(:action, :validate)

      form = to_form(changeset)

      socket =
        socket
        |> assign(:form, form)
        |> assign(:pending_template_id, default_template_id)

      {:noreply, socket}
    else
      # Normal validate without upload data - safe to update component
      campaign_params = Map.drop(campaign_params, ["_target"])

      {default_template_id, campaign_params} = Map.pop(campaign_params, "default_template_id")
      campaign_params = normalize_datetime_params(campaign_params)

      changeset =
        socket.assigns.campaign
        |> Campaigns.change_campaign(campaign_params)
        |> Map.put(:action, :validate)

      form = to_form(changeset)

      # Update parent socket
      socket =
        socket
        |> assign(:form, form)
        |> assign(:pending_template_id, default_template_id)

      update_form_component(socket,
        form: form,
        pending_template_id: default_template_id
      )

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("save", %{"campaign" => campaign_params}, socket) do
    if upload_in_progress?(socket) do
      {:noreply,
       socket
       |> put_flash(:error, "圖片上傳中，請稍候再試")
       |> tap(&update_form_component(&1))}
    else
      {default_template_id, campaign_params} = Map.pop(campaign_params, "default_template_id")

      campaign_params =
        campaign_params
        |> Map.drop(["_target"])
        |> normalize_datetime_params()
        |> handle_image_upload(socket)

      save_campaign(socket, socket.assigns.live_action, campaign_params, default_template_id)
    end
  end

  defp normalize_datetime_params(params) do
    params
    |> normalize_datetime_field(:starts_at)
    |> normalize_datetime_field(:ends_at)
    |> normalize_checkbox_field(:enable_protection)
  end

  defp normalize_datetime_field(params, field) when is_atom(field) do
    field_str = Atom.to_string(field)

    if value = params[field_str] do
      case parse_datetime_local(value) do
        {:ok, datetime} ->
          Map.put(params, field_str, datetime)

        {:error, _} ->
          params
      end
    else
      params
    end
  end

  defp parse_datetime_local(value) when is_binary(value) do
    # datetime-local format: "YYYY-MM-DDTHH:mm"
    case String.split(value, "T") do
      [date, time] ->
        case String.split(date, "-") do
          [year_str, month_str, day_str] ->
            case String.split(time, ":") do
              [hour_str, minute_str] ->
                year = LiveViewHelpers.parse_integer(year_str, nil)
                month = LiveViewHelpers.parse_integer(month_str, nil)
                day = LiveViewHelpers.parse_integer(day_str, nil)
                hour = LiveViewHelpers.parse_integer(hour_str, nil)
                minute = LiveViewHelpers.parse_integer(minute_str, nil)

                if year && month && day && hour && minute do
                  case NaiveDateTime.new(year, month, day, hour, minute, 0) do
                    {:ok, datetime} ->
                      {:ok, DateTime.from_naive!(datetime, "Etc/UTC")}

                    {:error, _} ->
                      {:error, :invalid_format}
                  end
                else
                  {:error, :invalid_format}
                end

              _ ->
                {:error, :invalid_format}
            end

          _ ->
            {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  defp parse_datetime_local(_), do: {:error, :invalid_format}

  defp normalize_checkbox_field(params, field) when is_atom(field) do
    field_str = Atom.to_string(field)

    value =
      case params[field_str] do
        "true" -> true
        "false" -> false
        true -> true
        false -> false
        "1" -> true
        "0" -> false
        _ -> false
      end

    Map.put(params, field_str, value)
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    socket = cancel_upload(socket, :background_image, ref)

    update_form_component(socket)

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear-uploaded-background", _params, socket) do
    socket = assign(socket, :latest_background_image_url, nil)

    update_form_component(socket, latest_background_image_url: nil)

    {:noreply, socket}
  end

  def handle_progress(:background_image, entry, socket) do
    require Logger

    Logger.debug(
      "handle_progress CALLED: entry.done? = #{entry.done?}, entry.ref = #{entry.ref}, entry.progress = #{entry.progress}%, entry.client_name = #{entry.client_name}"
    )

    update_form_component(socket)

    if entry.done? do
      Logger.debug("handle_progress: Entry is done, processing file...")

      case process_background_image_upload(socket) do
        {:ok, url} ->
          Logger.debug("handle_progress: upload completed #{url}")
          socket = assign(socket, :latest_background_image_url, url)
          update_form_component(socket, latest_background_image_url: url)
          {:noreply, socket}

        {:error, reason} ->
          Logger.error("Background image upload failed: #{inspect(reason)}")

          socket =
            socket
            |> put_flash(:error, "圖片上傳失敗，請重試")

          update_form_component(socket)
          {:noreply, socket}
      end
    else
      Logger.debug("handle_progress: Entry not done yet, progress = #{entry.progress}%")
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:cancel_upload, :background_image, ref}, socket) do
    socket = cancel_upload(socket, :background_image, ref)

    update_form_component(socket)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:clear_uploaded_background}, socket) do
    socket = assign(socket, :latest_background_image_url, nil)

    update_form_component(socket, latest_background_image_url: nil)

    {:noreply, socket}
  end

  @impl true
  def handle_info({PrizeModalComponent, :update_modal, attrs}, socket) do
    {:noreply, set_prize_modal(socket, attrs)}
  end

  @impl true
  def handle_info({PrizeModalComponent, :close_modal}, socket) do
    {:noreply, assign(socket, :prize_modal, default_prize_modal())}
  end

  @impl true
  def handle_info({PrizeModalComponent, :save_prize, payload}, socket) do
    process_prize_modal_save(socket, payload)
  end

  @impl true
  def handle_info({:validate_campaign, params}, socket) do
    # Handle validate event forwarded from component
    handle_event("validate", params, socket)
  end

  defp reload_winning_records(socket, winner_filter) do
    campaign = socket.assigns.campaign
    winners_page = socket.assigns[:winning_records_page] || 1
    winners_page_size = socket.assigns[:winning_records_page_size] || @winners_preview_limit
    sort_by = socket.assigns[:winning_records_sort_by] || "inserted_at"
    sort_order = socket.assigns[:winning_records_sort_order] || "desc"

    opts = %{
      page: winners_page,
      page_size: winners_page_size,
      status: if(winner_filter.status == "all", do: nil, else: winner_filter.status),
      search: if(winner_filter.search == "", do: nil, else: winner_filter.search),
      sort_by: sort_by,
      sort_order: sort_order
    }

    winning_records_result = Lottery.list_winning_records(campaign.id, opts)
    winning_summary = Lottery.winning_record_summary(campaign.id)

    socket
    |> assign(:winning_records, winning_records_result.items)
    |> assign(:winning_summary, winning_summary)
    |> assign(:winning_records_total, winning_records_result.total)
    |> assign(:winning_records_page, winning_records_result.page)
    |> assign(:winning_records_page_size, winning_records_result.page_size)
    |> assign(:winning_records_sort_by, sort_by)
    |> assign(:winning_records_sort_order, sort_order)
    |> assign(:winner_filter, winner_filter)
    |> assign(:last_refresh_time, DateTime.utc_now())
  end

  defp load_campaigns(socket) do
    admin_id = socket.assigns.current_admin.id

    opts = %{
      admin_id: admin_id,
      search: socket.assigns.search,
      status: socket.assigns.status_filter,
      page: socket.assigns.page,
      page_size: socket.assigns.page_size,
      sort_by: socket.assigns.sort_by,
      sort_order: socket.assigns.sort_order
    }

    result = Campaigns.list_campaigns(opts)

    socket
    |> assign(:campaigns, result.items)
    |> assign(:campaigns_total, result.total)
    |> assign(:campaigns_page, result.page)
    |> assign(:campaigns_page_size, result.page_size)
    |> assign(:stats, calculate_stats(result.items))
    |> assign(:alerts, smart_alerts(result.items))
  end

  defp parse_integer(nil, default), do: default

  defp parse_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_integer(value, _default) when is_integer(value), do: value
  defp parse_integer(_, default), do: default

  defp build_pagination_path(socket, page, page_size, sort_by \\ nil, sort_order \\ nil) do
    params =
      %{
        "page" => Integer.to_string(page),
        "page_size" => Integer.to_string(page_size),
        "search" => socket.assigns.search,
        "status" => socket.assigns.status_filter,
        "sort_by" => sort_by || socket.assigns.sort_by,
        "sort_order" => sort_order || socket.assigns.sort_order
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
      |> Map.new()

    ~p"/admin/campaigns?#{params}"
  end

  defp load_preview(socket, campaign_id, tab, opts) do
    admin_id = socket.assigns.current_admin.id
    campaign = Campaigns.get_campaign_for_admin!(campaign_id, admin_id)
    prizes_result = Campaigns.list_prizes(campaign.id, %{page: 1, page_size: 1000})
    prizes = prizes_result.items
    stats = Statistics.get_campaign_stats(campaign.id)
    email_stats = Emails.get_email_stats(campaign.id)

    winner_filter =
      Keyword.get(opts, :winner_filter, socket.assigns[:winner_filter] || @default_winner_filter)

    winner_filter = normalize_winner_filter(winner_filter)

    # Get pagination parameters from opts or socket assigns
    winners_page = Keyword.get(opts, :winners_page, socket.assigns[:winning_records_page] || 1)

    winners_page_size =
      Keyword.get(
        opts,
        :winners_page_size,
        socket.assigns[:winning_records_page_size] || @winners_preview_limit
      )

    sort_by =
      Keyword.get(
        opts,
        :winners_sort_by,
        socket.assigns[:winning_records_sort_by] || "inserted_at"
      )

    sort_order =
      Keyword.get(
        opts,
        :winners_sort_order,
        socket.assigns[:winning_records_sort_order] || "desc"
      )

    winning_records_opts = %{
      page: winners_page,
      page_size: winners_page_size,
      status: if(winner_filter.status == "all", do: nil, else: winner_filter.status),
      search: if(winner_filter.search == "", do: nil, else: winner_filter.search),
      sort_by: sort_by,
      sort_order: sort_order
    }

    winning_records_result = Lottery.list_winning_records(campaign.id, winning_records_opts)
    winning_records = winning_records_result.items
    winning_summary = Lottery.winning_record_summary(campaign.id)
    prize_templates_result = PrizeLibrary.list_templates(%{page: 1, page_size: 1000})
    prize_templates = prize_templates_result.items
    email_template_options_result = Emails.list_global_templates(%{page: 1, page_size: 1000})
    email_template_options = email_template_options_result.items

    operations =
      build_operations(stats, email_stats, prizes, winning_records, winning_summary)

    activity_logs = Campaigns.list_activity_logs(campaign.id, limit: 50)
    activity_feed = build_activity_feed(campaign, activity_logs)
    prize_filter = Keyword.get(opts, :prize_filter, @default_prize_filter)

    socket
    |> assign(:page_title, "Preview Campaign - #{campaign.name}")
    |> assign(:campaign, campaign)
    |> assign(:form, nil)
    |> assign(:stats, stats)
    |> assign(:email_stats, email_stats)
    |> assign(:winning_records, winning_records)
    |> assign(:winning_summary, winning_summary)
    |> assign(:winning_records_total, winning_records_result.total)
    |> assign(:winning_records_page, winning_records_result.page)
    |> assign(:winning_records_page_size, winning_records_result.page_size)
    |> assign(:winning_records_sort_by, sort_by)
    |> assign(:winning_records_sort_order, sort_order)
    |> assign(:operations, operations)
    |> assign(:activity_feed, activity_feed)
    |> assign(:active_tab, tab)
    |> assign(:prize_modal, default_prize_modal())
    |> assign(:prize_templates, prize_templates)
    |> assign(:email_template_options, email_template_options)
    |> assign(:winner_filter, winner_filter)
    |> assign(:last_refresh_time, DateTime.utc_now())
    |> assign_preview_prize_data(prizes, prize_filter)
  end

  defp assign_preview_prize_data(socket, prizes, filter \\ nil) do
    # Ensure prizes is always a list
    prizes_list =
      cond do
        is_list(prizes) -> prizes
        is_map(prizes) && Map.has_key?(prizes, :items) -> prizes.items || []
        true -> []
      end

    filter = normalize_prize_filter(filter || socket.assigns[:prize_filter])
    filtered_prizes = filter_prizes(prizes_list, filter)

    socket
    |> assign(:prizes, prizes_list)
    |> assign(:prize_filter, filter)
    |> assign(:filtered_prizes, filtered_prizes)
    |> assign(:prize_stats, build_prize_stats(prizes_list))
  end

  defp build_prize_modal_payload(socket, prize_params) do
    modal = socket.assigns.prize_modal
    campaign = socket.assigns.campaign
    admin_id = socket.assigns.current_admin.id

    normalized_params =
      prize_params
      |> normalize_quantity_field(:total_quantity)
      |> normalize_quantity_field(:remaining_quantity)

    %{
      mode: modal.mode,
      prize: modal.prize,
      prize_params: normalized_params,
      campaign_id: campaign.id,
      admin_id: admin_id
    }
  end

  defp process_prize_modal_save(socket, %{
         mode: mode,
         prize: prize,
         prize_params: prize_params,
         campaign_id: campaign_id,
         admin_id: admin_id
       }) do
    result =
      case mode do
        "edit" ->
          Campaigns.update_prize(prize, prize_params, admin_id: admin_id)

        _ ->
          params = Map.put(prize_params, "campaign_id", campaign_id)
          Campaigns.create_prize(params, admin_id: admin_id)
      end

    case result do
      {:ok, saved_prize} ->
        prizes_result = Campaigns.list_prizes(campaign_id, %{page: 1, page_size: 1000})
        prizes = prizes_result.items
        message = prize_action_message(mode, saved_prize)

        socket =
          socket
          |> assign_preview_prize_data(prizes)
          |> assign(:prize_modal, default_prize_modal())
          |> assign(:prize_templates, PrizeLibrary.list_templates())
          |> put_flash(:info, message)

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, set_prize_modal(socket, %{form: to_form(changeset)})}
    end
  end

  defp normalize_prize_filter(nil), do: @default_prize_filter

  defp normalize_prize_filter(filter) do
    %{
      search: String.trim(Map.get(filter, "search", Map.get(filter, :search, ""))),
      type: Map.get(filter, "type", Map.get(filter, :type, "all"))
    }
  end

  defp normalize_winner_filter(nil), do: @default_winner_filter

  defp normalize_winner_filter(filter) do
    %{
      status: Map.get(filter, "status", Map.get(filter, :status, "all")),
      search: String.trim(Map.get(filter, "search", Map.get(filter, :search, "")))
    }
  end

  defp normalize_quantity_field(params, field) when is_atom(field) do
    field_str = to_string(field)
    value = Map.get(params, field_str) || Map.get(params, field)

    cond do
      value == "" || value == nil ->
        Map.put(params, field_str, nil)

      is_binary(value) ->
        case Integer.parse(value) do
          {num, _} ->
            Map.put(params, field_str, num)

          _ ->
            Map.put(params, field_str, nil)
        end

      is_integer(value) ->
        Map.put(params, field_str, value)

      true ->
        Map.put(params, field_str, nil)
    end
  end

  defp filter_prizes(prizes, %{search: search, type: type}) do
    prizes
    |> Enum.filter(fn prize ->
      match_type? = type in ["all", nil] || prize_type(prize) == type

      match_search? =
        search == "" ||
          (prize_name(prize) &&
             String.contains?(String.downcase(prize_name(prize)), String.downcase(search))) ||
          (prize_description(prize) &&
             String.contains?(String.downcase(prize_description(prize)), String.downcase(search)))

      match_type? && match_search?
    end)
  end

  defp build_prize_stats(prizes) when is_list(prizes) do
    stats =
      Enum.reduce(prizes, %{
        total_quantity: 0,
        remaining_quantity: 0,
        protected_count: 0,
        probability_sum: 0.0,
        has_unlimited?: false
      }, fn prize, acc ->
        protected_count = acc.protected_count + if(prize.is_protected, do: 1, else: 0)
        probability_sum = acc.probability_sum + probability_value(prize)

        acc =
          acc
          |> Map.put(:protected_count, protected_count)
          |> Map.put(:probability_sum, probability_sum)

        case prize.total_quantity do
          nil ->
            Map.put(acc, :has_unlimited?, true)

          total_qty ->
            remaining_qty = prize.remaining_quantity || 0

            acc
            |> Map.update!(:total_quantity, &(&1 + total_qty))
            |> Map.update!(:remaining_quantity, &(&1 + remaining_qty))
        end
      end)

    no_prize? = Enum.any?(prizes, &(&1.prize_type == "no_prize"))

    warnings =
      []
      |> maybe_add_warning(stats.probability_sum > 100.0, "所有獎品的總機率超過 100%。")
      |> maybe_add_warning(stats.probability_sum < 95.0, "總機率明顯低於 100%，請確認是否有未設獎品。")
      |> maybe_add_warning(!no_prize?, "建議設定至少一個未中獎獎品，以平衡體驗。")
      |> maybe_add_warning(
        !stats.has_unlimited? && stats.total_quantity > 0 && stats.remaining_quantity <= 0,
        "所有獎品已發完，請儘速補貨。"
      )

    %{
      count: length(prizes),
      total_quantity: stats.total_quantity,
      remaining_quantity: stats.remaining_quantity,
      has_unlimited?: stats.has_unlimited?,
      protected_count: stats.protected_count,
      probability_sum: Float.round(stats.probability_sum, 2),
      warnings: warnings
    }
  end

  # Fallback for non-list input (shouldn't happen, but defensive programming)
  defp build_prize_stats(prizes) do
    prizes_list =
      cond do
        is_map(prizes) && Map.has_key?(prizes, :items) -> prizes.items || []
        true -> []
      end

    build_prize_stats(prizes_list)
  end

  defp maybe_add_warning(warnings, true, message), do: [message | warnings]
  defp maybe_add_warning(warnings, _condition, _message), do: warnings

  defp probability_value(%{probability: nil}), do: 0.0

  defp probability_value(%{probability: %Decimal{} = probability}) do
    Decimal.to_float(probability)
  end

  defp probability_value(%{probability: probability}) do
    probability
    |> Decimal.new()
    |> Decimal.to_float()
  rescue
    _ -> 0.0
  end

  # 辅助函数：从模板或 prize 获取字段值
  defp prize_name(%{source_template: %{name: name}}) when not is_nil(name), do: name
  defp prize_name(%{name: name}), do: name
  defp prize_name(_), do: nil

  defp prize_description(%{source_template: %{description: desc}}) when not is_nil(desc), do: desc
  defp prize_description(%{description: desc}), do: desc
  defp prize_description(_), do: nil

  defp prize_image_url(%{source_template: %{image_url: url}}) when not is_nil(url), do: url
  defp prize_image_url(%{image_url: url}), do: url
  defp prize_image_url(_), do: nil

  defp prize_type(%{source_template: %{prize_type: type}}) when not is_nil(type), do: type
  defp prize_type(%{prize_type: type}), do: type
  defp prize_type(_), do: nil

  defp prize_email_template_label(%{email_template: %{name: name}}) when is_binary(name),
    do: name

  defp prize_email_template_label(%{email_template_id: id}) when not is_nil(id),
    do: "已選擇模板"

  defp prize_email_template_label(_), do: "跟隨活動預設"

  defp default_prize_modal do
    %{
      open?: false,
      mode: nil,
      title: nil,
      prize: nil,
      form: nil,
      selected_template_id: nil,
      template_locked_fields: []
    }
  end

  defp set_prize_modal(socket, attrs) do
    modal = Map.merge(socket.assigns.prize_modal, attrs)
    assign(socket, :prize_modal, modal)
  end

  defp prize_action_message("edit", prize) do
    "#{prize_name(prize) || "獎品"} 修改完成"
  end

  defp prize_action_message(_mode, prize) do
    "#{prize_name(prize) || "獎品"} 建立完成"
  end

  defp calculate_stats(campaigns) do
    now = DateTime.utc_now()

    %{
      total: length(campaigns),
      active: Enum.count(campaigns, &(&1.status == "active")),
      upcoming:
        Enum.count(campaigns, fn campaign ->
          campaign.starts_at && DateTime.compare(campaign.starts_at, now) == :gt
        end),
      ending_soon: Enum.count(campaigns, &ending_soon?(&1, now))
    }
  end

  defp smart_alerts(campaigns) do
    now = DateTime.utc_now()

    campaigns
    |> Enum.flat_map(fn campaign ->
      []
      |> maybe_add_draft_alert(campaign, now)
      |> maybe_add_ending_alert(campaign, now)
      |> maybe_add_disabled_alert(campaign)
      |> maybe_add_branding_alert(campaign)
    end)
    |> Enum.sort_by(& &1.priority, :desc)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(4)
  end

  defp build_operations(stats, email_stats, prizes, winning_records, winning_summary) do
    total_prizes = length(prizes)

    {remaining, total_quantity, has_unlimited?} =
      Enum.reduce(prizes, {0, 0, false}, fn prize, {rem, total, unlimited?} ->
        case prize.total_quantity do
          nil ->
            {rem, total, true}

          total_qty ->
            rem_qty = prize.remaining_quantity || 0
            {rem + rem_qty, total + total_qty, unlimited?}
        end
      end)

    pending_winners =
      Map.get(winning_summary, "pending_submit", 0) +
        Map.get(winning_summary, "pending_process", 0)

    [
      %{
        id: "engagement",
        label: "參與總數",
        value: stats.total_entries,
        subtitle: "#{stats.unique_users} 位唯一玩家",
        tone: :indigo
      },
      %{
        id: "prizes",
        label: "獎品庫存",
        value: total_prizes,
        subtitle: prize_subtitle(total_quantity, remaining, has_unlimited?),
        tone: :amber
      },
      %{
        id: "winners",
        label: "待處理獎項",
        value: pending_winners,
        subtitle: "#{winning_summary["total"] || length(winning_records)} 筆紀錄",
        tone: :emerald
      },
      %{
        id: "emails",
        label: "郵件成功率",
        value: "#{email_stats.success_rate}%",
        subtitle: "#{email_stats.pending} 封待寄出",
        tone: :slate
      }
    ]
  end

  defp build_activity_feed(campaign, activity_logs) do
    # Build base feed items from campaign metadata
    base_items = [
      %{
        id: "created",
        title: "建立活動",
        description: "活動建立完成，等待配置。",
        timestamp: campaign.inserted_at,
        icon: "hero-bolt"
      }
    ]

    # Check if there's a date range change in activity logs
    has_date_change =
      Enum.any?(activity_logs, fn log ->
        log.action == "update_campaign" && log.field in ["starts_at", "ends_at"]
      end)

    # Only show "設定檔期" if there's a date change in logs, or if it's a new campaign
    scheduled_item =
      if has_date_change || Enum.empty?(activity_logs) do
        %{
          id: "scheduled",
          title: "設定檔期",
          description: format_date_range(campaign),
          timestamp: campaign.updated_at,
          icon: "hero-calendar"
        }
      end

    # Add active status if campaign is active
    active_item =
      if campaign.status == "active" do
        %{
          id: "active",
          title: "活動啟動",
          description: "活動目前運行中。",
          timestamp: campaign.starts_at,
          icon: "hero-play"
        }
      end

    # Convert activity logs to feed items
    log_items =
      Enum.map(activity_logs, fn log ->
        format_activity_log_item(log)
      end)

    # Combine all items, filter out nil, and sort by timestamp
    (base_items ++ [scheduled_item, active_item] ++ log_items)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  defp format_activity_log_item(log) do
    admin_name = if log.admin, do: log.admin.name || log.admin.email || "系統", else: "系統"
    description = build_activity_description(log, admin_name)

    %{
      id: "log-#{log.id}",
      title: build_activity_title(log, admin_name),
      description: description,
      timestamp: log.inserted_at,
      icon: activity_icon(log.action)
    }
  end

  defp build_activity_title(log, admin_name) do
    case log.action do
      "update_campaign" ->
        if log.field do
          "#{admin_name} 修改了活動"
        else
          "#{admin_name} 修改了活動"
        end

      "create_prize" ->
        "#{admin_name} 新增了獎品"

      "update_prize" ->
        "#{admin_name} 修改了獎品"

      "delete_prize" ->
        "#{admin_name} 刪除了獎品"

      _ ->
        "#{admin_name} 執行了操作"
    end
  end

  defp build_activity_description(log, _admin_name) do
    case log.action do
      "update_campaign" ->
        if log.field do
          field_label = field_label(log.field)
          from_val = format_log_value(log.from_value)
          to_val = format_log_value(log.to_value)
          "#{field_label}：#{from_val} → #{to_val}"
        else
          "活動設定已更新"
        end

      "create_prize" ->
        prize_name = get_in(log.metadata || %{}, ["prize_name"]) || "未知獎品"
        prize_type = get_in(log.metadata || %{}, ["prize_type"]) || ""
        type_label = prize_type_label(prize_type)
        "新增獎品：#{prize_name}#{if type_label != "", do: " (#{type_label})", else: ""}"

      "update_prize" ->
        prize_name = get_in(log.metadata || %{}, ["prize_name"]) || "未知獎品"

        if log.field do
          field_label = field_label(log.field)
          from_val = format_log_value(log.from_value)
          to_val = format_log_value(log.to_value)
          "#{prize_name} 的 #{field_label}：#{from_val} → #{to_val}"
        else
          "獎品 #{prize_name} 已更新"
        end

      "delete_prize" ->
        prize_name = get_in(log.metadata || %{}, ["prize_name"]) || "未知獎品"
        "刪除獎品：#{prize_name}"

      _ ->
        "執行了操作"
    end
  end

  defp activity_icon("update_campaign"), do: "hero-pencil-square"
  defp activity_icon("create_prize"), do: "hero-plus-circle"
  defp activity_icon("update_prize"), do: "hero-pencil-square"
  defp activity_icon("delete_prize"), do: "hero-trash"
  defp activity_icon(_), do: "hero-information-circle"

  defp field_label("name"), do: "名稱"
  defp field_label("description"), do: "描述"
  defp field_label("status"), do: "狀態"
  defp field_label("starts_at"), do: "開始時間"
  defp field_label("ends_at"), do: "結束時間"
  defp field_label("background_image_url"), do: "背景圖片"
  defp field_label("theme_color"), do: "主題顏色"
  defp field_label("total_quantity"), do: "總數量"
  defp field_label("remaining_quantity"), do: "剩餘數量"
  defp field_label("daily_limit"), do: "每日上限"
  defp field_label("probability"), do: "中獎機率"
  defp field_label("is_protected"), do: "保護狀態"
  defp field_label("prize_type"), do: "獎品類型"
  defp field_label("prize_code"), do: "兌換碼"
  defp field_label(field), do: field

  defp format_log_value(nil), do: "—"
  defp format_log_value(""), do: "—"
  defp format_log_value(value) when is_binary(value), do: value
  defp format_log_value(value), do: inspect(value)

  defp prize_type_label("physical"), do: "實體"
  defp prize_type_label("virtual"), do: "虛擬"
  defp prize_type_label("no_prize"), do: "未中獎"
  defp prize_type_label(_), do: ""

  defp maybe_add_draft_alert(alerts, %{status: "draft"} = campaign, now) do
    cond do
      campaign.starts_at &&
        DateTime.compare(campaign.starts_at, now) == :gt &&
          DateTime.diff(campaign.starts_at, now, :hour) <= 72 ->
        [
          %{
            id: "#{campaign.id}-draft",
            title: "#{campaign.name} 即將開始",
            description: "此活動處於草稿狀態，建議在開始前完成內容與審核。",
            action: "前往設定",
            href: ~p"/admin/campaigns/#{campaign.id}/preview",
            type: :warning,
            type_label: "即將開始",
            priority: 3
          }
          | alerts
        ]

      true ->
        alerts
    end
  end

  defp maybe_add_draft_alert(alerts, _campaign, _now), do: alerts

  defp maybe_add_ending_alert(alerts, campaign, now) do
    if ending_soon?(campaign, now) do
      [
        %{
          id: "#{campaign.id}-ending",
          title: "#{campaign.name} 即將結束",
          description: "請確認獎品庫存與通知流程，確保活動完美收尾。",
          action: "檢視活動",
          href: ~p"/admin/campaigns/#{campaign.id}/preview",
          type: :info,
          type_label: "提醒",
          priority: 2
        }
        | alerts
      ]
    else
      alerts
    end
  end

  defp maybe_add_disabled_alert(alerts, %{status: "disabled"} = campaign) do
    [
      %{
        id: "#{campaign.id}-disabled",
        title: "#{campaign.name} 已停用",
        description: "檢視是否需要重新啟用或複製此活動。",
        action: "管理活動",
        href: ~p"/admin/campaigns/#{campaign.id}/preview",
        type: :neutral,
        type_label: "狀態",
        priority: 1
      }
      | alerts
    ]
  end

  defp maybe_add_disabled_alert(alerts, _campaign), do: alerts

  defp maybe_add_branding_alert(alerts, campaign) do
    if is_nil(campaign.background_image_url) ||
         String.trim(to_string(campaign.background_image_url)) == "" do
      [
        %{
          id: "#{campaign.id}-branding",
          title: "#{campaign.name} 缺少背景圖",
          description: "加入品牌視覺可以提升玩家的沉浸感與信任度。",
          action: "上傳素材",
          href: ~p"/admin/campaigns/#{campaign.id}/edit",
          type: :info,
          type_label: "品牌",
          priority: 1
        }
        | alerts
      ]
    else
      alerts
    end
  end

  defp ending_soon?(%{status: "active", ends_at: ends_at}, now) when not is_nil(ends_at) do
    DateTime.compare(ends_at, now) == :gt && DateTime.diff(ends_at, now, :hour) <= 72
  end

  defp ending_soon?(_campaign, _now), do: false

  defp alert_badge_class(:warning), do: "bg-amber-100 text-amber-800"
  defp alert_badge_class(:info), do: "bg-indigo-100 text-indigo-800"
  defp alert_badge_class(:neutral), do: "bg-slate-100 text-slate-800"
  defp alert_badge_class(_), do: "bg-slate-100 text-slate-800"

  defp timeline_badge_class(campaign) do
    case timeline_stage(campaign) do
      :starting_soon -> "bg-emerald-100 text-emerald-800"
      :upcoming -> "bg-slate-100 text-slate-700"
      :ending_soon -> "bg-amber-100 text-amber-800"
      :active -> "bg-indigo-100 text-indigo-800"
      :ended -> "bg-slate-100 text-slate-600"
      :paused -> "bg-rose-100 text-rose-800"
      _ -> "bg-slate-100 text-slate-600"
    end
  end

  defp timeline_badge_label(campaign) do
    case timeline_stage(campaign) do
      :starting_soon -> "即將開始"
      :upcoming -> "排程中"
      :ending_soon -> "即將結束"
      :active -> "運行中"
      :ended -> "已結束"
      :paused -> "已停用"
      _ -> "狀態未知"
    end
  end

  defp timeline_stage(campaign) do
    now = DateTime.utc_now()

    cond do
      campaign.status == "draft" && campaign.starts_at &&
        DateTime.compare(campaign.starts_at, now) == :gt &&
          DateTime.diff(campaign.starts_at, now, :hour) <= 72 ->
        :starting_soon

      campaign.status == "draft" && campaign.starts_at &&
          DateTime.compare(campaign.starts_at, now) == :gt ->
        :upcoming

      ending_soon?(campaign, now) ->
        :ending_soon

      campaign.status == "active" ->
        :active

      campaign.status == "ended" ->
        :ended

      campaign.status == "disabled" ->
        :paused

      true ->
        :unknown
    end
  end

  @impl true
  def render(assigns) do
    # Log upload status before rendering (only for new/edit actions)
    require Logger

    upload =
      if assigns.live_action in [:new, :edit] do
        upload_val = Map.get(assigns.uploads || %{}, :background_image)

        if is_nil(upload_val) do
          Logger.error(
            "Rendering FormComponent: @uploads is #{inspect(assigns.uploads)}, background_upload is nil! This will prevent file uploads."
          )
        else
          Logger.debug(
            "Rendering FormComponent: background_upload.ref = #{upload_val.ref}, entries = #{length(upload_val.entries)}"
          )
        end

        upload_val
      else
        nil
      end

    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :admin, current_nav: :campaigns}}>
      <.page_container>
        <%= cond do %>
          <% @live_action in [:new, :edit] -> %>
            <.live_component
              module={DobbyWeb.Admin.CampaignLive.FormComponent}
              id={@campaign.id || :new}
              title={@page_title}
              action={@live_action}
              campaign={@campaign}
              form={@form}
              current_admin={@current_admin}
              latest_background_image_url={@latest_background_image_url}
              background_upload={upload}
              return_to={~p"/admin/campaigns"}
            />
          <% @live_action == :preview -> %>
            <div class="w-full space-y-6">
              <!-- Header -->
              <div class="flex items-center justify-end mb-8">
                <.primary_button navigate={~p"/admin/campaigns/#{@campaign.id}/edit"}>
                  <.icon name="hero-pencil" class="h-4 w-4" /> 編輯活動
                </.primary_button>
              </div>

    <!-- Campaign Hero -->
              <div class="bg-base-100 text-base-content rounded-2xl shadow-lg shadow-primary/10 border border-base-300 overflow-hidden transition-colors">
                <div class="relative">
                  <div :if={@campaign.background_image_url} class="h-64 w-full overflow-hidden">
                    <img
                      src={@campaign.background_image_url}
                      alt="Campaign Background"
                      class="w-full h-full object-cover"
                    />
                  </div>
                  <div
                    :if={!@campaign.background_image_url}
                    class="h-64 w-full bg-gradient-to-br from-indigo-500 via-purple-500 to-pink-500 flex items-center justify-center"
                  >
                    <div class="text-center text-white">
                      <.icon name="hero-ticket" class="h-16 w-16 mx-auto mb-4 opacity-50" />
                      <p class="text-lg font-semibold opacity-75">無背景圖片</p>
                    </div>
                  </div>
                  <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-transparent to-transparent">
                  </div>
                  <div class="absolute inset-0 flex flex-col justify-between p-8 text-white">
                    <div class="pt-4 space-y-3">
                      <div class="flex items-center gap-3 flex-wrap">
                        <span class={[
                          "inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold",
                          status_color(@campaign.status)
                        ]}>
                          {status_label(@campaign.status)}
                        </span>
                        <div class="flex items-center gap-2 rounded-full bg-white/20 backdrop-blur-sm px-3 py-1.5 text-[11px] font-mono text-white/90">
                          <span class="truncate max-w-[200px]">活动ID: {@campaign.id}</span>
                          <button
                            type="button"
                            id={"campaign-preview-id-copy-#{@campaign.id}"}
                            phx-hook="CopyToClipboard"
                            phx-click-bubble="false"
                            data-copy-text={@campaign.id}
                            data-copy-success-label="已复制"
                            aria-label="複製活動 ID"
                            class="inline-flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full border border-white/30 text-white hover:bg-white/20 transition-colors"
                          >
                            <.icon name="hero-document-duplicate" class="h-3.5 w-3.5" />
                          </button>
                        </div>
                      </div>
                      <h1 class="text-5xl font-black leading-tight">{@campaign.name || "未命名活動"}</h1>
                    </div>
                    <div class="pb-4">
                      <p
                        :if={@campaign.description}
                        class="text-xl font-medium text-white/95 max-w-2xl"
                      >
                        {@campaign.description}
                      </p>
                      <p :if={!@campaign.description} class="text-lg text-white/70 italic">
                        尚未提供描述
                      </p>
                    </div>
                  </div>
                </div>
              </div>

    <!-- Tabs Navigation -->
              <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 transition-colors">
                <div class="border-b border-base-200">
                  <nav class="flex overflow-x-auto" aria-label="Tabs">
                    <button
                      phx-click="switch_tab"
                      phx-value-tab="overview"
                      class={[
                        "px-6 py-4 text-sm font-semibold border-b-2 transition-colors whitespace-nowrap",
                        if(@active_tab == "overview",
                          do: "border-indigo-500 text-indigo-600",
                          else:
                            "border-transparent text-slate-500 hover:text-slate-700 hover:border-slate-300"
                        )
                      ]}
                    >
                      <.icon name="hero-information-circle" class="h-4 w-4 inline mr-2" /> 概覽
                    </button>
                    <button
                      phx-click="switch_tab"
                      phx-value-tab="prizes"
                      class={[
                        "px-6 py-4 text-sm font-semibold border-b-2 transition-colors whitespace-nowrap",
                        if(@active_tab == "prizes",
                          do: "border-indigo-500 text-indigo-600",
                          else:
                            "border-transparent text-slate-500 hover:text-slate-700 hover:border-slate-300"
                        )
                      ]}
                    >
                      <.icon name="hero-gift" class="h-4 w-4 inline mr-2" /> 獎品管理
                      <span class="ml-2 px-2 py-0.5 text-xs bg-slate-100 text-slate-600 rounded-full">
                        {length(@prizes)}
                      </span>
                    </button>
                    <button
                      phx-click="switch_tab"
                      phx-value-tab="winners"
                      class={[
                        "px-6 py-4 text-sm font-semibold border-b-2 transition-colors whitespace-nowrap",
                        if(@active_tab == "winners",
                          do: "border-indigo-500 text-indigo-600",
                          else:
                            "border-transparent text-slate-500 hover:text-slate-700 hover:border-slate-300"
                        )
                      ]}
                    >
                      <.icon name="hero-trophy" class="h-4 w-4 inline mr-2" /> 獲獎記錄
                      <span class="ml-2 px-2 py-0.5 text-xs bg-slate-100 text-slate-600 rounded-full">
                        {(@winning_summary && @winning_summary["total"]) || 0}
                      </span>
                    </button>
                    <button
                      phx-click="switch_tab"
                      phx-value-tab="activity"
                      class={[
                        "px-6 py-4 text-sm font-semibold border-b-2 transition-colors whitespace-nowrap",
                        if(@active_tab == "activity",
                          do: "border-indigo-500 text-indigo-600",
                          else:
                            "border-transparent text-slate-500 hover:text-slate-700 hover:border-slate-300"
                        )
                      ]}
                    >
                      <.icon name="hero-clock" class="h-4 w-4 inline mr-2" /> 活動日誌
                    </button>
                  </nav>
                </div>

    <!-- Tab Content -->
                <div class="p-6">
                  <%= cond do %>
                    <% @active_tab == "overview" -> %>
                      {render_overview_tab(assigns)}
                    <% @active_tab == "prizes" -> %>
                      {render_prizes_tab(assigns)}
                    <% @active_tab == "winners" -> %>
                      {render_winners_tab(assigns)}
                    <% @active_tab == "activity" -> %>
                      {render_activity_tab(assigns)}
                  <% end %>
                </div>
              </div>
            </div>
            <.live_component
              module={DobbyWeb.Admin.CampaignLive.PrizeModalComponent}
              id="prize-modal"
              prize_modal={@prize_modal}
              campaign={@campaign}
              prize_templates={@prize_templates}
              email_template_options={@email_template_options}
              current_admin={@current_admin}
            />
          <% true -> %>
            <div class="py-6">
              <div class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_220px] xl:grid-cols-[minmax(0,1fr)_240px]">
                <!-- Main content -->
                <section class="space-y-6">
                  <div class="flex flex-wrap items-center justify-between gap-4 mb-8">
                    <.page_header
                      title="活動總覽"
                      subtitle="快速掌握所有活動的狀態與優先事項"
                    />
                    <.primary_button navigate={~p"/admin/campaigns/new"}>
                      <.icon name="hero-plus" class="h-4 w-4" /> 建立活動
                    </.primary_button>
                  </div>

                  <div class="grid gap-4 md:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
                    <.search_input
                      name="search"
                      value={@search}
                      placeholder="搜尋活動名稱或描述..."
                      phx_change="search"
                      phx_debounce="300"
                    />

                    <form phx-change="filter_status">
                      <label class="sr-only" for="campaign-status-select">篩選狀態</label>
                      <.select
                        id="campaign-status-select"
                        name="status"
                        value={@status_filter}
                        options={[
                          {"all", "全部狀態"},
                          {"draft", "草稿"},
                          {"active", "進行中"},
                          {"ended", "已結束"},
                          {"disabled", "已停用"}
                        ]}
                        class="w-full rounded-2xl"
                      />
                    </form>
                  </div>

                  <div
                    :if={Enum.empty?(@campaigns)}
                    class="rounded-3xl border-2 border-dashed border-base-300 bg-base-100/90 text-base-content p-12 text-center"
                  >
                    <p class="text-lg font-semibold">目前沒有符合條件的活動</p>
                    <p class="text-sm text-base-content/70 mt-2">試著調整搜尋條件，或建立一個新的活動。</p>
                    <.primary_button navigate={~p"/admin/campaigns/new"} class="mt-6">
                      <.icon name="hero-plus" class="h-4 w-4" /> 建立活動
                    </.primary_button>
                  </div>

                  <div :if={!Enum.empty?(@campaigns)} class="grid gap-4 xl:grid-cols-2">
                    <div
                      :for={campaign <- @campaigns}
                      id={"campaign-card-#{campaign.id}"}
                      phx-click="open_preview"
                      phx-value-id={campaign.id}
                      class="group relative rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm transition-all hover:-translate-y-1 hover:shadow-2xl hover:shadow-primary/20 cursor-pointer"
                    >
                      <div class="flex flex-col gap-2 lg:flex-row lg:items-start lg:justify-between">
                        <div class="flex-1">
                          <p class="text-xs font-semibold uppercase tracking-[0.25em] text-base-content/50">
                            campaign
                          </p>
                          <h2 class="text-lg font-semibold text-base-content group-hover:text-primary transition-colors">
                            {campaign.name || "未命名活動"}
                          </h2>
                          <p class="text-sm text-base-content/70 mt-0.5 line-clamp-2">
                            {campaign.description || "尚未提供描述，建議補上活動亮點。"}
                          </p>
                          <div class="mt-2 flex items-center gap-2">
                            <p class="text-[10px] text-base-content/50">
                              <span class="text-base-content/70">活动ID: </span>
                              <span class="font-mono break-all">{campaign.id}</span>
                            </p>
                            <button
                              type="button"
                              id={"campaign-card-copy-#{campaign.id}"}
                              phx-hook="CopyToClipboard"
                              phx-click-bubble="false"
                              data-copy-text={campaign.id}
                              data-copy-success-label="已复制"
                              aria-label="複製活動 ID"
                              class="inline-flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full border border-base-200 text-base-content/60 hover:border-primary/40 hover:text-primary transition-colors"
                            >
                              <.icon name="hero-document-duplicate" class="h-3.5 w-3.5" />
                            </button>
                          </div>
                        </div>
                        <div class="flex items-center gap-2 lg:flex-col lg:items-end text-xs font-semibold">
                          <span class={[
                            "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold",
                            timeline_badge_class(campaign)
                          ]}>
                            {timeline_badge_label(campaign)}
                          </span>
                          <div class="flex flex-col items-end gap-0.5 text-[10px] text-base-content/50">
                            <span>
                              <span class="text-base-content/70">建立：</span>
                              {format_uk_datetime(campaign.inserted_at)}
                            </span>
                            <span>
                              <span class="text-base-content/70">更新：</span>
                              {format_uk_datetime(campaign.updated_at)}
                            </span>
                          </div>
                        </div>
                      </div>

                      <div class="mt-3">
                        <div class="rounded-xl border border-base-200 bg-base-200/50 p-3">
                          <p class="text-[10px] uppercase tracking-wide text-base-content/50">期間</p>
                          <p class="text-xs font-semibold text-base-content mt-0.5">
                            {format_date_range(campaign)}
                          </p>
                          <p class="text-[10px] text-base-content/70 mt-0.5">
                            {relative_time_label(campaign)}
                          </p>
                        </div>
                      </div>

                      <div class="mt-4 flex flex-wrap items-center justify-between gap-2 border-t border-base-200 pt-3">
                        <div class="text-xs text-base-content/70 flex items-center gap-1">
                          <.icon name="hero-cursor-arrow-rays" class="h-4 w-4 text-primary" />
                          點擊卡片可立即跳轉到 Preview 做進階管理
                        </div>
                        <div class="flex flex-wrap gap-2">
                          <button
                            type="button"
                            phx-click="toggle_status"
                            phx-click-bubble="false"
                            phx-value-id={campaign.id}
                            class="inline-flex items-center gap-1 rounded-full border border-base-200 px-3 py-1.5 text-xs font-semibold text-base-content/70 hover:border-primary/40 hover:text-primary transition-colors"
                          >
                            {if campaign.status == "active", do: "停用", else: "啟用"}
                          </button>
                          <button
                            type="button"
                            phx-click="delete"
                            phx-click-bubble="false"
                            phx-value-id={campaign.id}
                            data-confirm="確定刪除此活動？"
                            class="inline-flex items-center gap-1 rounded-full border border-error/50 px-3 py-1.5 text-xs font-semibold text-error hover:border-error/70"
                          >
                            刪除
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>

                  <.pagination
                    :if={!Enum.empty?(@campaigns)}
                    page={@campaigns_page}
                    page_size={@campaigns_page_size}
                    total={@campaigns_total}
                    path={~p"/admin/campaigns"}
                    params={
                      %{
                        "search" => @search,
                        "status" => @status_filter,
                        "sort_by" => @sort_by,
                        "sort_order" => @sort_order
                      }
                    }
                  />
                </section>

    <!-- Sidebar -->
                <aside class="space-y-6">
                  <div class="space-y-3">
                    <div class="rounded-2xl bg-slate-900 text-white p-3 shadow-lg">
                      <p class="text-xs uppercase tracking-[0.2em] text-slate-400">總活動</p>
                      <p class="text-3xl font-semibold mt-1">{@stats.total}</p>
                      <p class="text-[10px] text-slate-400 mt-0.5">所有活動的集中控制台</p>
                    </div>
                    <div class="grid gap-2">
                      <div class="rounded-xl border border-indigo-100 bg-indigo-50/50 p-2.5">
                        <p class="text-[10px] text-indigo-600 font-semibold uppercase tracking-wide">
                          進行中
                        </p>
                        <p class="text-2xl font-semibold text-indigo-900 mt-0.5">{@stats.active}</p>
                        <p class="text-[10px] text-indigo-500">目前正在運行的活動</p>
                      </div>
                      <div class="rounded-xl border border-emerald-100 bg-emerald-50/50 p-2.5">
                        <p class="text-[10px] text-emerald-600 font-semibold uppercase tracking-wide">
                          即將開始
                        </p>
                        <p class="text-2xl font-semibold text-emerald-900 mt-0.5">
                          {@stats.upcoming}
                        </p>
                        <p class="text-[10px] text-emerald-500">排程在未來的活動</p>
                      </div>
                      <div class="rounded-xl border border-amber-100 bg-amber-50/50 p-2.5">
                        <p class="text-[10px] text-amber-600 font-semibold uppercase tracking-wide">
                          即將結束
                        </p>
                        <p class="text-2xl font-semibold text-amber-900 mt-0.5">
                          {@stats.ending_soon}
                        </p>
                        <p class="text-[10px] text-amber-500">72 小時內到期的活動</p>
                      </div>
                    </div>
                  </div>

                  <div class="space-y-3">
                    <div class="flex items-center justify-between text-base-content">
                      <p class="text-sm font-semibold">智慧提醒</p>
                      <span class="text-xs text-base-content/50">{length(@alerts)} 則</span>
                    </div>
                    <div
                      :if={Enum.empty?(@alerts)}
                      class="rounded-2xl border border-base-300 bg-base-100 p-4 text-sm text-base-content/70"
                    >
                      目前沒有需要注意的事項。
                    </div>
                    <div
                      :for={alert <- @alerts}
                      id={"alert-#{alert.id}"}
                      class="rounded-2xl border border-base-300 bg-base-100 p-4 space-y-2 shadow-sm"
                    >
                      <div class="flex items-center justify-between gap-3">
                        <p class="text-sm font-semibold text-base-content">{alert.title}</p>
                        <span class={[
                          "text-xs font-semibold px-2 py-1 rounded-full",
                          alert_badge_class(alert.type)
                        ]}>
                          {alert.type_label}
                        </span>
                      </div>
                      <p class="text-xs text-base-content/70 leading-relaxed">{alert.description}</p>
                      <.link
                        :if={alert.href}
                        navigate={alert.href}
                        class="text-xs font-semibold text-primary hover:text-primary/80 inline-flex items-center gap-1"
                      >
                        {alert.action}
                        <.icon name="hero-arrow-right" class="h-3 w-3" />
                      </.link>
                    </div>
                  </div>
                </aside>
              </div>
            </div>
        <% end %>
      </.page_container>
    </Layouts.app>
    """
  end

  defp normalize_preview_tab(tab) when tab in @preview_tabs, do: tab
  defp normalize_preview_tab(_), do: @default_preview_tab

  defp preview_loaded?(%{assigns: %{campaign: %Campaign{id: campaign_id}}}, id),
    do: campaign_id == id

  defp preview_loaded?(_, _), do: false

  defp status_color("active"), do: "bg-green-100 text-green-800"
  defp status_color("draft"), do: "bg-gray-100 text-gray-800"
  defp status_color("ended"), do: "bg-blue-100 text-blue-800"
  defp status_color("disabled"), do: "bg-red-100 text-red-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"

  defp status_label("active"), do: "Active"
  defp status_label("draft"), do: "Draft"
  defp status_label("ended"), do: "Ended"
  defp status_label("disabled"), do: "Disabled"
  defp status_label(status), do: String.capitalize(status || "draft")

  defp format_date(nil), do: "-"

  defp format_date(datetime) when is_struct(datetime, DateTime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp format_date(_), do: "-"

  defp format_date_range(%{starts_at: nil, ends_at: nil}), do: "尚未設定"

  defp format_date_range(%{starts_at: start_at, ends_at: ends_at}) do
    [format_short_date(start_at), format_short_date(ends_at)]
    |> Enum.reject(&(&1 == "未設定"))
    |> Enum.join(" - ")
    |> case do
      "" -> "尚未設定"
      value -> value
    end
  end

  defp format_short_date(nil), do: "未設定"

  defp format_short_date(datetime) when is_struct(datetime, DateTime) do
    Calendar.strftime(datetime, "%Y/%m/%d")
  end

  defp format_short_date(_), do: "未設定"

  defp relative_time_label(%{status: "disabled"}), do: "已停用"
  defp relative_time_label(%{status: "ended", ends_at: nil}), do: "已結束"

  defp relative_time_label(%{status: "ended", ends_at: ends_at}) do
    "已於 #{format_short_date(ends_at)} 結束"
  end

  defp relative_time_label(campaign) do
    now = DateTime.utc_now()

    cond do
      campaign.status in ["draft"] && campaign.starts_at &&
          DateTime.compare(campaign.starts_at, now) == :gt ->
        diff = DateTime.diff(campaign.starts_at, now, :second)
        "將於 #{humanize_distance(diff)}後開始"

      campaign.status == "active" && campaign.ends_at &&
          DateTime.compare(campaign.ends_at, now) == :gt ->
        diff = DateTime.diff(campaign.ends_at, now, :second)
        "剩餘 #{humanize_distance(diff)}"

      campaign.status == "active" && campaign.ends_at &&
          DateTime.compare(campaign.ends_at, now) != :gt ->
        "結束時間已過"

      campaign.status == "draft" ->
        "等待啟動"

      true ->
        "時間未定"
    end
  end

  defp humanize_distance(seconds) when seconds <= 0 do
    humanize_distance(abs(seconds))
  end

  defp humanize_distance(seconds) do
    cond do
      seconds >= 86_400 ->
        "#{div(seconds, 86_400)} 天"

      seconds >= 3_600 ->
        "#{div(seconds, 3_600)} 小時"

      seconds >= 60 ->
        "#{div(seconds, 60)} 分鐘"

      true ->
        "#{seconds} 秒"
    end
  end

  # Tab render functions
  defp render_overview_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Tab Header -->
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 class="text-2xl font-semibold text-slate-900">概覽</h2>
          <p class="text-sm text-slate-500 mt-1">查看活動的整體統計與詳細資訊</p>
        </div>
      </div>

    <!-- Quick Stats -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div class="bg-gradient-to-br from-indigo-50 to-indigo-100 border border-indigo-200 rounded-xl p-5">
          <p class="text-xs uppercase tracking-[0.3em] text-indigo-600 mb-2">總參與數</p>
          <p class="text-3xl font-bold text-indigo-900">{@stats.total_entries}</p>
        </div>
        <div class="bg-gradient-to-br from-emerald-50 to-emerald-100 border border-emerald-200 rounded-xl p-5">
          <p class="text-xs uppercase tracking-[0.3em] text-emerald-600 mb-2">獲獎數</p>
          <p class="text-3xl font-bold text-emerald-900">{@stats.prizes_issued}</p>
        </div>
        <div class="bg-gradient-to-br from-amber-50 to-amber-100 border border-amber-200 rounded-xl p-5">
          <p class="text-xs uppercase tracking-[0.3em] text-amber-600 mb-2">轉換率</p>
          <p class="text-3xl font-bold text-amber-900">{@stats.conversion_rate}%</p>
        </div>
        <div class="bg-gradient-to-br from-slate-50 to-slate-100 border border-slate-200 rounded-xl p-5">
          <p class="text-xs uppercase tracking-[0.3em] text-slate-600 mb-2">獎品數</p>
          <p class="text-3xl font-bold text-slate-900">{length(@prizes)}</p>
        </div>
      </div>

    <!-- Campaign Details -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="bg-slate-50 rounded-xl p-6">
          <p class="text-sm text-slate-500 mb-2">開始時間</p>
          <p class="text-xl font-semibold text-slate-900">{format_date(@campaign.starts_at)}</p>
        </div>
        <div class="bg-slate-50 rounded-xl p-6">
          <p class="text-sm text-slate-500 mb-2">結束時間</p>
          <p class="text-xl font-semibold text-slate-900">{format_date(@campaign.ends_at)}</p>
        </div>
      </div>

      <div :if={@campaign.rules_text} class="bg-slate-50 rounded-xl p-6">
        <h2 class="text-xl font-semibold mb-4 text-slate-900">活動規則</h2>
        <p class="text-slate-700 whitespace-pre-wrap leading-relaxed">{@campaign.rules_text}</p>
      </div>

      <div
        :if={@campaign.enable_protection}
        class="bg-amber-50 border border-amber-200 rounded-xl p-6"
      >
        <div class="flex items-start gap-4">
          <.icon name="hero-shield-check" class="h-6 w-6 text-amber-600 flex-shrink-0 mt-0.5" />
          <div>
            <h3 class="font-semibold text-amber-900 mb-2">大獎保護已啟用</h3>
            <p class="text-sm text-amber-800">
              前 {@campaign.protection_count} 次抽獎不會中大獎
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_winners_tab(assigns) do
    ~H"""
    <div id="winners-tab-container" class="space-y-6" phx-hook="DownloadCSV">
      <!-- Tab Header -->
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 class="text-2xl font-semibold text-slate-900">獲獎記錄</h2>
          <p class="text-sm text-slate-500 mt-1">查看所有獲獎記錄</p>
        </div>
        <div class="flex items-center gap-2">
          <span :if={@last_refresh_time} class="text-xs text-slate-500">
            最後更新：{format_time(@last_refresh_time)}
          </span>
          <.secondary_button phx-click="refresh_preview">
            <.icon name="hero-arrow-path" class="h-4 w-4" /> 重新整理
          </.secondary_button>
          <.primary_button phx-click="export_winners_csv">
            <.icon name="hero-arrow-down-tray" class="h-4 w-4" /> 匯出 CSV
          </.primary_button>
        </div>
      </div>

    <!-- Enhanced Summary Cards -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4 mb-6">
        <div class="bg-gradient-to-br from-emerald-50 to-emerald-100 border border-emerald-200 rounded-xl p-5">
          <p class="text-xs uppercase tracking-[0.3em] text-emerald-600 mb-2">總獲獎數</p>
          <p class="text-3xl font-bold text-emerald-900">
            {@winning_summary["total"] || 0}
          </p>
        </div>
        <div class="bg-gradient-to-br from-slate-50 to-slate-100 border border-slate-200 rounded-xl p-5">
          <p class="text-xs uppercase tracking-[0.3em] text-slate-600 mb-2">等待填寫資料</p>
          <p class="text-3xl font-bold text-slate-900">
            {@winning_summary["pending_submit"] || 0}
          </p>
        </div>
        <div class="bg-gradient-to-br from-amber-50 to-amber-100 border border-amber-200 rounded-xl p-5">
          <p class="text-xs uppercase tracking-[0.3em] text-amber-600 mb-2">待處理 / 寄送</p>
          <p class="text-3xl font-bold text-amber-900">
            {@winning_summary["pending_process"] || 0}
          </p>
          <p :if={@winning_summary["pending_process_pct"]} class="text-xs text-amber-700 mt-1">
            {@winning_summary["pending_process_pct"]}% 占比
          </p>
        </div>
        <div class="bg-gradient-to-br from-slate-50 to-slate-100 border border-slate-200 rounded-xl p-5">
          <p class="text-xs uppercase tracking-[0.3em] text-slate-600 mb-2">已完成發送</p>
          <p class="text-3xl font-bold text-slate-900">
            {@winning_summary["fulfilled"] || 0}
          </p>
        </div>
        <div class="bg-gradient-to-br from-indigo-50 to-indigo-100 border border-indigo-200 rounded-xl p-5">
          <p class="text-xs uppercase tracking-[0.3em] text-indigo-600 mb-2">近24小時</p>
          <p class="text-3xl font-bold text-indigo-900">
            {@winning_summary["last24h"] || 0}
          </p>
        </div>
      </div>

    <!-- Filters -->
      <div class="flex flex-wrap items-center gap-4 p-4 bg-base-100 rounded-xl border border-base-300 text-base-content">
        <div class="flex items-center gap-2">
          <span class="text-sm font-semibold text-slate-700">狀態：</span>
          <div class="flex gap-2 flex-wrap">
            <button
              phx-click="filter_winners"
              phx-value-status="all"
              class={[
                "px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors",
                if(Map.get(@winner_filter || %{}, :status, "all") == "all",
                  do: "bg-indigo-100 text-indigo-700",
                  else: "bg-slate-100 text-slate-600 hover:bg-slate-200"
                )
              ]}
            >
              全部
            </button>
            <button
              phx-click="filter_winners"
              phx-value-status="pending_submit"
              class={[
                "px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors",
                if(Map.get(@winner_filter || %{}, :status, "all") == "pending_submit",
                  do: "bg-slate-100 text-slate-700",
                  else: "bg-slate-50 text-slate-600 hover:bg-slate-100"
                )
              ]}
            >
              等待填寫資料
            </button>
            <button
              phx-click="filter_winners"
              phx-value-status="pending_process"
              class={[
                "px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors",
                if(Map.get(@winner_filter || %{}, :status, "all") == "pending_process",
                  do: "bg-amber-100 text-amber-700",
                  else: "bg-amber-50 text-amber-600 hover:bg-amber-100"
                )
              ]}
            >
              待處理 / 寄送
            </button>
            <button
              phx-click="filter_winners"
              phx-value-status="fulfilled"
              class={[
                "px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors",
                if(Map.get(@winner_filter || %{}, :status, "all") == "fulfilled",
                  do: "bg-emerald-100 text-emerald-700",
                  else: "bg-emerald-50 text-emerald-600 hover:bg-emerald-100"
                )
              ]}
            >
              已完成發送
            </button>
            <button
              phx-click="filter_winners"
              phx-value-status="expired"
              class={[
                "px-3 py-1.5 text-xs font-semibold rounded-lg transition-colors",
                if(Map.get(@winner_filter || %{}, :status, "all") == "expired",
                  do: "bg-rose-100 text-rose-700",
                  else: "bg-rose-50 text-rose-600 hover:bg-rose-100"
                )
              ]}
            >
              逾期未完成
            </button>
          </div>
        </div>
        <div class="flex-1 min-w-[200px]">
          <form phx-change="search_winners" phx-debounce="300">
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400"
              />
              <input
                type="text"
                name="search"
                value={Map.get(@winner_filter || %{}, :search, "")}
                placeholder="搜尋姓名、Email 或交易號..."
                class="w-full pl-10 pr-4 py-2 text-sm border border-slate-300 rounded-lg focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500"
              />
            </div>
          </form>
        </div>
      </div>

    <!-- Empty State -->
      <div
        :if={@winning_records == []}
        class="text-center py-12 bg-base-200/50 rounded-xl border border-base-300 text-base-content"
      >
        <.icon name="hero-trophy" class="mx-auto h-12 w-12 text-base-content/30 mb-4" />
        <p class="text-base-content/60 font-medium">
          {if Map.get(@winner_filter || %{}, :status, "all") != "all" ||
                Map.get(@winner_filter || %{}, :search, "") != "",
              do: "沒有符合篩選條件的獲獎記錄",
              else: "尚未有獲獎記錄"}
        </p>
      </div>

    <!-- Records Table -->
      <div
        :if={@winning_records != []}
        class="overflow-x-auto bg-base-100 rounded-xl border border-base-300"
      >
        <table class="min-w-full divide-y divide-base-300 bg-base-100 text-base-content">
          <thead class="bg-base-200/80 text-xs font-semibold uppercase tracking-[0.2em] text-base-content/70">
            <tr>
              <th class="px-4 py-3 text-left">
                <button
                  phx-click="sort_winners"
                  phx-value-field="name"
                  class="flex items-center gap-2 hover:text-base-content transition-colors"
                >
                  <span>獲獎者</span>
                  <span :if={(@winning_records_sort_by || "inserted_at") == "name"}>
                    <.icon
                      name={
                        if (@winning_records_sort_order || "desc") == "desc",
                          do: "hero-arrow-down",
                          else: "hero-arrow-up"
                      }
                      class="h-4 w-4"
                    />
                  </span>
                </button>
              </th>
              <th class="px-4 py-3 text-left">
                交易號
              </th>
              <th class="px-4 py-3 text-left">
                <button
                  phx-click="sort_winners"
                  phx-value-field="prize_name"
                  class="flex items-center gap-2 hover:text-base-content transition-colors"
                >
                  <span>獎品</span>
                  <span :if={(@winning_records_sort_by || "inserted_at") == "prize_name"}>
                    <.icon
                      name={
                        if (@winning_records_sort_order || "desc") == "desc",
                          do: "hero-arrow-down",
                          else: "hero-arrow-up"
                      }
                      class="h-4 w-4"
                    />
                  </span>
                </button>
              </th>
              <th class="px-4 py-3 text-left">
                <button
                  phx-click="sort_winners"
                  phx-value-field="status"
                  class="flex items-center gap-2 hover:text-base-content transition-colors"
                >
                  <span>狀態</span>
                  <span :if={(@winning_records_sort_by || "inserted_at") == "status"}>
                    <.icon
                      name={
                        if (@winning_records_sort_order || "desc") == "desc",
                          do: "hero-arrow-down",
                          else: "hero-arrow-up"
                      }
                      class="h-4 w-4"
                    />
                  </span>
                </button>
              </th>
              <th class="px-4 py-3 text-left">
                <button
                  phx-click="sort_winners"
                  phx-value-field="inserted_at"
                  class="flex items-center gap-2 hover:text-base-content transition-colors"
                >
                  <span>時間</span>
                  <span :if={(@winning_records_sort_by || "inserted_at") == "inserted_at"}>
                    <.icon
                      name={
                        if (@winning_records_sort_order || "desc") == "desc",
                          do: "hero-arrow-down",
                          else: "hero-arrow-up"
                      }
                      class="h-4 w-4"
                    />
                  </span>
                </button>
              </th>
              <th class="px-4 py-3 text-right">
                操作
              </th>
            </tr>
          </thead>
          <tbody class="bg-base-100 divide-y divide-base-200 text-sm">
            <tr
              :for={record <- @winning_records}
              id={"winner-preview-#{record.id}"}
              class="hover:bg-base-200/50 transition-colors"
            >
              <td class="px-4 py-4 whitespace-nowrap">
                <p class="font-medium text-base-content">{record.name || "—"}</p>
                <p class="text-xs text-base-content/70">{record.email || "No email"}</p>
              </td>
              <td class="px-4 py-4">
                <div class="flex items-center gap-2">
                  <span class="text-sm font-mono text-base-content/80">
                    {if record.transaction_number,
                      do: record.transaction_number.transaction_number,
                      else: "—"}
                  </span>
                  <button
                    :if={record.transaction_number}
                    id={"copy-tx-#{record.id}"}
                    data-copy-text={record.transaction_number.transaction_number}
                    data-copy-success-label="已複製"
                    phx-hook="CopyToClipboard"
                    class="text-base-content/40 hover:text-base-content/70"
                    title="複製交易號"
                  >
                    <.icon name="hero-clipboard" class="h-4 w-4" />
                  </button>
                </div>
              </td>
              <td class="px-4 py-4">
                <p class="text-base-content">
                  {record.prize && prize_name(record.prize)}
                </p>
                <p class="text-xs text-base-content/70 capitalize">
                  {record.prize && prize_type(record.prize)}
                </p>
              </td>
              <td class="px-4 py-4">
                <span class={[
                  "inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold",
                  winner_status_color(record.status)
                ]}>
                  {winner_status_label(record.status)}
                </span>
              </td>
              <td class="px-4 py-4 text-base-content/70">
                {format_date(record.inserted_at)}
              </td>
              <td class="px-4 py-4 text-right">
                <div class="flex items-center justify-end gap-2">
                  <button
                    :if={record.status != "fulfilled"}
                    phx-click="mark_winner_status"
                    phx-value-id={record.id}
                    phx-value-status="fulfilled"
                    class="text-xs text-primary hover:text-primary/80 font-medium"
                    title="標記為已完成"
                  >
                    完成
                  </button>
                  <button
                    :if={
                      record.email &&
                        (record.status == "pending_process" ||
                           (record.status == "fulfilled" &&
                              record.prize &&
                              prize_type(record.prize) == "virtual"))
                    }
                    phx-click="resend_winner_email"
                    phx-value-id={record.id}
                    class="text-xs text-success hover:text-success/80 font-medium"
                    title="重新發送郵件"
                  >
                    重新寄出通知
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <div
          :if={!Enum.empty?(@winning_records) || @winning_records_total > 0}
          class="flex flex-col sm:flex-row items-center justify-between gap-4 mt-6"
        >
          <div class="flex items-center gap-2 text-sm text-slate-600">
            <span>顯示</span>
            <.select
              name="winners_page_size"
              value={Integer.to_string(@winning_records_page_size)}
              options={[
                {"10", "10"},
                {"20", "20"},
                {"25", "25"},
                {"50", "50"},
                {"100", "100"}
              ]}
              phx_change="change_winners_page_size"
              class="rounded-lg border border-slate-200 px-2 py-1 text-sm focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500"
            />
            <span>條，共 {@winning_records_total} 條記錄</span>
          </div>

          <div class="flex items-center gap-1">
            <button
              :if={@winning_records_page > 1}
              phx-click="go_to_winners_page"
              phx-value-page={@winning_records_page - 1}
              class="inline-flex items-center justify-center rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50"
            >
              <.icon name="hero-chevron-left" class="w-4 h-4" />
            </button>
            <button
              :if={@winning_records_page <= 1}
              disabled
              class="inline-flex items-center justify-center rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-300 cursor-not-allowed"
            >
              <.icon name="hero-chevron-left" class="w-4 h-4" />
            </button>

            <span class="px-3 py-2 text-sm text-slate-600">
              第 {@winning_records_page} 頁
            </span>

            <button
              :if={@winning_records_page < ceil(@winning_records_total / @winning_records_page_size)}
              phx-click="go_to_winners_page"
              phx-value-page={@winning_records_page + 1}
              class="inline-flex items-center justify-center rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50"
            >
              <.icon name="hero-chevron-right" class="w-4 h-4" />
            </button>
            <button
              :if={@winning_records_page >= ceil(@winning_records_total / @winning_records_page_size)}
              disabled
              class="inline-flex items-center justify-center rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-300 cursor-not-allowed"
            >
              <.icon name="hero-chevron-right" class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp render_activity_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h2 class="text-2xl font-semibold text-base-content">活動日誌</h2>
          <p class="text-sm text-base-content/60 mt-1">查看活動的完整時間線與重要事件</p>
        </div>
        <button
          phx-click="refresh_preview"
          class="inline-flex items-center gap-2 px-4 py-2 bg-base-100 border border-base-300 text-base-content/80 rounded-lg hover:bg-base-200/70 font-semibold transition-colors"
        >
          <.icon name="hero-arrow-path" class="h-4 w-4" /> 重新整理
        </button>
      </div>

      <div class="space-y-4">
        <div
          :for={activity <- @activity_feed}
          id={"activity-#{activity.id}"}
          class="relative flex gap-4 pb-6 last:pb-0"
        >
          <div class="flex-shrink-0">
            <div class="flex h-10 w-10 items-center justify-center rounded-full bg-indigo-100 dark:bg-indigo-900/30">
              <.icon name={activity.icon} class="h-5 w-5 text-indigo-600 dark:text-indigo-400" />
            </div>
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <h3 class="text-sm font-semibold text-base-content">{activity.title}</h3>
                <p class="text-sm text-base-content/70 mt-1">{activity.description}</p>
                <p class="text-xs text-base-content/50 mt-2">
                  {format_relative_time(activity.timestamp)}
                </p>
              </div>
            </div>
          </div>
          <div
            :if={activity != List.last(@activity_feed)}
            class="absolute left-5 top-10 bottom-0 w-0.5 bg-base-300"
          >
          </div>
        </div>

        <div
          :if={Enum.empty?(@activity_feed)}
          class="text-center py-12 bg-base-200/50 rounded-xl border border-base-300"
        >
          <p class="text-base-content/60">尚無活動記錄</p>
        </div>
      </div>
    </div>
    """
  end

  defp render_prizes_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Tab Header -->
      <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 class="text-2xl font-semibold text-slate-900">獎品管理</h2>
          <p class="text-sm text-slate-500 mt-1">透過視覺化卡片快速掌握狀態</p>
        </div>
        <div class="flex items-center gap-2">
          <.secondary_button phx-click="refresh_preview">
            <.icon name="hero-arrow-path" class="h-4 w-4" /> 重新整理
          </.secondary_button>
          <.primary_button phx-click="open_prize_modal" phx-value-mode="new">
            <.icon name="hero-plus" class="h-4 w-4" /> 建立 / 匯入獎品
          </.primary_button>
        </div>
      </div>

      <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div class="rounded-2xl border border-base-300 bg-base-100 p-4 text-base-content">
          <p class="text-xs uppercase tracking-[0.3em] text-slate-400">獎品總數</p>
          <p class="text-3xl font-semibold text-slate-900 mt-2">{@prize_stats.count}</p>
          <p class="text-xs text-slate-500 mt-1">已設定的獎品品項</p>
        </div>
        <div class="rounded-2xl border border-indigo-200 bg-indigo-50 p-4">
          <p class="text-xs uppercase tracking-[0.3em] text-indigo-500">庫存 / 總量</p>
          <p class="text-3xl font-semibold text-indigo-900 mt-2">
            {format_quantity_display(
              @prize_stats.remaining_quantity,
              @prize_stats.total_quantity,
              unlimited?: @prize_stats.has_unlimited?
            )}
          </p>
          <p class="text-xs text-indigo-600 mt-1">目前可用庫存</p>
        </div>
        <div class="rounded-2xl border border-emerald-200 bg-emerald-50 p-4">
          <p class="text-xs uppercase tracking-[0.3em] text-emerald-500">保護獎品</p>
          <p class="text-3xl font-semibold text-emerald-900 mt-2">{@prize_stats.protected_count}</p>
          <p class="text-xs text-emerald-600 mt-1">啟用保護的獎品數</p>
        </div>
        <div class="rounded-2xl border border-amber-200 bg-amber-50 p-4">
          <p class="text-xs uppercase tracking-[0.3em] text-amber-500">總機率</p>
          <p class="text-3xl font-semibold text-amber-900 mt-2">{@prize_stats.probability_sum}%</p>
          <p class="text-xs text-amber-600 mt-1">所有獎品機率加總</p>
        </div>
      </div>

      <div
        :if={@prize_stats.warnings != []}
        class="rounded-2xl border border-rose-200 bg-rose-50 p-4 space-y-2"
      >
        <div class="flex items-center gap-2 text-rose-700">
          <.icon name="hero-exclamation-triangle" class="h-5 w-5" />
          <p class="font-semibold">建議檢查以下項目</p>
        </div>
        <ul class="list-disc pl-5 text-sm text-rose-700 space-y-1">
          <li :for={warning <- Enum.reverse(@prize_stats.warnings)}>{warning}</li>
        </ul>
      </div>

      <form phx-change="prize_filter" class="grid gap-3 md:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]">
        <.search_input
          name="filter[search]"
          value={@prize_filter.search}
          placeholder="搜尋獎品名稱或描述..."
          in_form={true}
          phx_debounce="500"
        />
        <.select
          name="filter[type]"
          value={@prize_filter.type}
          options={[
            {"all", "全部類型"},
            {"physical", "實體獎品"},
            {"virtual", "虛擬獎品"},
            {"no_prize", "未中獎"}
          ]}
          phx-change="filter_prize_type"
          class="rounded-2xl"
        />
      </form>

      <div
        :if={@filtered_prizes == []}
        class="text-center py-12 bg-base-200/50 rounded-xl border border-base-300 text-base-content"
      >
        <p class="text-base-content/70 mb-4">尚未添加任何獎品</p>
        <button
          type="button"
          phx-click="open_prize_modal"
          phx-value-mode="new"
          class="inline-flex items-center gap-2 rounded-xl bg-indigo-600 px-6 py-2.5 text-sm font-semibold text-white shadow hover:bg-indigo-500"
        >
          <.icon name="hero-plus" class="h-4 w-4" /> 新增第一個獎品
        </button>
      </div>

      <div :if={@filtered_prizes != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          :for={prize <- @filtered_prizes}
          id={"prize-preview-#{prize.id}"}
          class="rounded-2xl border border-base-300 bg-base-100 p-5 space-y-4 shadow-sm transition-all hover:-translate-y-1 hover:shadow-xl hover:shadow-primary/20"
        >
          <div class="relative overflow-hidden rounded-2xl bg-base-200 h-36 flex items-center justify-center">
            <img
              :if={prize_image_url(prize)}
              src={prize_image_url(prize)}
              alt={prize_name(prize)}
              class="h-full w-full object-cover"
            />
            <div
              :if={!prize_image_url(prize)}
              class="flex flex-col items-center justify-center text-base-content/40"
            >
              <.icon name="hero-photo" class="h-8 w-8 mb-2" />
              <span class="text-xs">尚未設定圖片</span>
            </div>
          </div>

          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="text-lg font-semibold text-base-content">{prize_name(prize)}</p>
              <p class="text-xs text-base-content/70 mt-1">{prize_type_label(prize_type(prize))}</p>
            </div>
            <span
              :if={@campaign.enable_protection && prize.is_protected}
              class="inline-flex items-center gap-1 rounded-full bg-amber-100 px-3 py-1 text-xs font-semibold text-amber-700"
            >
              <.icon name="hero-shield-check" class="h-3.5 w-3.5" /> 保護中
            </span>
          </div>

          <p class="text-sm leading-relaxed line-clamp-2 min-h-[3rem] text-base-content/80">
            <span :if={prize_description(prize)}>
              {prize_description(prize)}
            </span>
            <span :if={!prize_description(prize)} class="text-base-content/50 italic">
              尚未提供描述
            </span>
          </p>

          <dl class="grid grid-cols-2 gap-3 text-xs">
            <div class="rounded-xl bg-base-200/60 p-3">
              <dt class="text-base-content/60">庫存狀態</dt>
              <dd class="text-sm font-semibold text-base-content">
                {format_quantity_display(prize.remaining_quantity, prize.total_quantity)}
              </dd>
            </div>
            <div class="rounded-xl bg-base-200/60 p-3">
              <dt class="text-base-content/60">每日上限</dt>
              <dd class="text-sm font-semibold text-base-content">
                {prize.daily_limit || "未設定"}
              </dd>
            </div>
            <div class="rounded-xl bg-base-200/60 p-3">
              <dt class="text-base-content/60">機率</dt>
              <dd class="text-sm font-semibold text-base-content">{format_probability(prize)}</dd>
            </div>
            <div class="rounded-xl bg-base-200/60 p-3">
              <dt class="text-base-content/60">來源模板</dt>
              <dd class="text-sm font-semibold text-base-content">
                {if prize.source_template_id, do: "已連結", else: "新增後自動建立"}
              </dd>
            </div>
            <div class="rounded-xl bg-base-200/60 p-3">
              <dt class="text-base-content/60">郵件模板</dt>
              <dd class="text-sm font-semibold text-base-content">
                {prize_email_template_label(prize)}
              </dd>
            </div>
          </dl>

          <form
            class="flex flex-wrap items-center gap-3 rounded-xl border border-base-300 bg-base-200/50 px-3 py-3 text-xs text-base-content"
            phx-submit="quick_adjust_quantity"
          >
            <input type="hidden" name="prize_id" value={prize.id} />
            <div class="flex items-center gap-2">
              <.icon name="hero-adjustments-horizontal" class="h-4 w-4 text-base-content/50" />
              <span class="font-semibold text-base-content/80">快速調整庫存</span>
            </div>
            <div class="flex items-center gap-2">
              <label class="text-base-content/60" for={"quantity-#{prize.id}"}>剩餘</label>
              <input
                id={"quantity-#{prize.id}"}
                type="number"
                name="quantity"
                min="0"
                value={if is_nil(prize.remaining_quantity), do: "", else: prize.remaining_quantity}
                placeholder={if is_nil(prize.total_quantity), do: "不限量", else: "0"}
                class="w-24 rounded-lg border border-base-300 bg-base-100 px-2 py-1 text-base-content focus:border-primary focus:ring-primary"
              />
            </div>
            <button
              type="submit"
              class="inline-flex items-center gap-1 rounded-lg border border-base-200 px-3 py-1.5 font-semibold text-base-content/70 hover:border-primary/40 hover:text-primary transition-colors"
            >
              <.icon name="hero-check" class="h-3.5 w-3.5" /> 更新
            </button>
          </form>

          <div class="grid grid-cols-3 gap-2 pt-2">
            <button
              type="button"
              phx-click="open_prize_modal"
              phx-value-mode="edit"
              phx-value-prize_id={prize.id}
              class="inline-flex items-center justify-center gap-1 rounded-lg border border-indigo-200 px-3 py-2 text-sm font-semibold text-indigo-700 hover:bg-indigo-50 transition-colors"
            >
              <.icon name="hero-pencil-square" class="h-4 w-4" /> 編輯
            </button>
            <button
              :if={@campaign.enable_protection}
              type="button"
              phx-click="toggle_prize_protection"
              phx-value-id={prize.id}
              class={[
                "inline-flex items-center justify-center gap-1 rounded-lg border px-3 py-2 text-sm font-semibold transition-colors",
                prize.is_protected &&
                  "border-emerald-200 text-emerald-700 hover:bg-emerald-50",
                !prize.is_protected &&
                  "border-slate-200 text-slate-600 hover:bg-slate-50"
              ]}
            >
              <.icon name="hero-shield-exclamation" class="h-4 w-4" />
              {if prize.is_protected, do: "取消保護", else: "啟用保護"}
            </button>
            <button
              type="button"
              phx-click="delete_prize"
              phx-value-id={prize.id}
              data-confirm="確定刪除此獎品？"
              class="inline-flex items-center justify-center gap-1 rounded-lg border border-rose-200 px-3 py-2 text-sm font-semibold text-rose-600 hover:bg-rose-50 transition-colors"
            >
              <.icon name="hero-trash" class="h-4 w-4" /> 刪除
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Prize modal rendering moved to PrizeModalComponent

  defp build_winners_pagination_path(socket, page, page_size) do
    campaign = socket.assigns.campaign
    page = page || socket.assigns[:winning_records_page] || 1
    page_size = page_size || socket.assigns[:winning_records_page_size] || @winners_preview_limit
    winner_filter = socket.assigns[:winner_filter] || @default_winner_filter
    sort_by = socket.assigns[:winning_records_sort_by] || "inserted_at"
    sort_order = socket.assigns[:winning_records_sort_order] || "desc"

    params =
      %{
        "tab" => "winners",
        "winners_page" => Integer.to_string(page),
        "winners_page_size" => Integer.to_string(page_size),
        "winners_sort_by" => sort_by,
        "winners_sort_order" => sort_order
      }
      |> Map.merge(
        if winner_filter.status != "all",
          do: %{"status" => winner_filter.status},
          else: %{}
      )
      |> Map.merge(
        if winner_filter.search != "",
          do: %{"search" => winner_filter.search},
          else: %{}
      )
      |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
      |> Map.new()

    ~p"/admin/campaigns/#{campaign.id}/preview?#{params}"
  end

  defp build_winners_csv(records) do
    rows =
      [["姓名", "Email", "交易號", "獎品", "狀態", "時間"] | Enum.map(records, &winner_csv_row/1)]

    rows
    |> Enum.map_join("\n", fn row ->
      row
      |> Enum.map(&csv_escape/1)
      |> Enum.join(",")
    end)
  end

  defp winner_csv_row(record) do
    prize_name =
      case record.prize do
        nil -> "-"
        prize -> prize_name(prize) || "-"
      end

    transaction_number =
      if record.transaction_number do
        record.transaction_number.transaction_number
      else
        "-"
      end

    [
      record.name || "",
      record.email || "",
      transaction_number,
      prize_name,
      winner_status_label(record.status),
      format_date(record.inserted_at)
    ]
  end

  defp csv_escape(nil), do: "\"\""

  defp csv_escape(value) when is_binary(value) do
    escaped = String.replace(value, "\"", "\"\"")
    "\"#{escaped}\""
  end

  defp csv_escape(value), do: csv_escape(to_string(value))

  defp winner_status_color("fulfilled"), do: "bg-emerald-100 text-emerald-800"
  defp winner_status_color("pending_process"), do: "bg-amber-100 text-amber-800"
  defp winner_status_color("pending_submit"), do: "bg-slate-100 text-slate-800"
  defp winner_status_color("expired"), do: "bg-rose-100 text-rose-800"
  defp winner_status_color(_), do: "bg-gray-100 text-gray-800"

  defp winner_status_label("pending_submit"), do: "等待得獎者填寫資料"
  defp winner_status_label("pending_process"), do: "待客服處理 / 寄送"
  defp winner_status_label("fulfilled"), do: "贈品已完成發送"
  defp winner_status_label("expired"), do: "逾期未完成"
  defp winner_status_label(_), do: "未知"

  defp format_relative_time(datetime) when is_struct(datetime, DateTime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "剛剛"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)} 分鐘前"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)} 小時前"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)} 天前"
      true -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
    end
  end

  defp format_relative_time(_), do: "未知時間"

  defp format_time(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_time(_), do: "—"

  defp format_uk_datetime(datetime) when is_struct(datetime, DateTime) do
    Calendar.strftime(datetime, "%d/%m/%Y %H:%M")
  end

  defp format_uk_datetime(_), do: "未知時間"

  defp prize_subtitle(_total_quantity, _remaining, true), do: "不限量"

  defp prize_subtitle(total_quantity, remaining, _unlimited?)
       when not is_nil(total_quantity) and total_quantity > 0 do
    percentage = Float.round(remaining / total_quantity * 100, 1)
    "#{remaining}/#{total_quantity} (#{percentage}%)"
  end

  defp prize_subtitle(_total_quantity, _remaining, _unlimited?), do: "0/0"

  # 格式化数量显示：nil 表示不限量
  defp format_quantity_display(remaining, total, opts \\ []) do
    unlimited? = Keyword.get(opts, :unlimited?, is_nil(total))

    cond do
      unlimited? ->
        "不限量"

      is_nil(total) ->
        "不限量"

      true ->
        remaining_value = if is_nil(remaining), do: 0, else: remaining
        "#{remaining_value}/#{total}"
    end
  end

  defp format_probability(prize) do
    value = Float.round(probability_value(prize), 2)

    if value == 0.0 do
      "未設定"
    else
      "#{value}%"
    end
  end

  defp update_form_component(socket, extra_assigns \\ []) do
    if socket.assigns.live_action in [:new, :edit] do
      base_assigns = [
        id: socket.assigns.campaign.id || :new,
        campaign: socket.assigns.campaign,
        title: socket.assigns.page_title,
        action: socket.assigns.live_action,
        return_to: ~p"/admin/campaigns",
        current_admin: socket.assigns.current_admin,
        form: socket.assigns.form,
        latest_background_image_url: socket.assigns[:latest_background_image_url],
        background_upload: background_upload(socket),
        pending_template_id: socket.assigns[:pending_template_id]
      ]

      assigns = Keyword.merge(base_assigns, extra_assigns)

      send_update(DobbyWeb.Admin.CampaignLive.FormComponent, assigns)
    end
  end

  defp save_campaign(socket, :edit, campaign_params, default_template_id) do
    admin_id = socket.assigns.current_admin.id

    case Campaigns.update_campaign(socket.assigns.campaign, campaign_params, admin_id: admin_id) do
      {:ok, campaign} ->
        maybe_assign_default_template(campaign, default_template_id)

        {:noreply,
         socket
         |> put_flash(:info, "Campaign updated successfully")
         |> push_navigate(to: ~p"/admin/campaigns/#{campaign.id}/preview?reload=1")}

      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(changeset)

        socket =
          socket
          |> assign(:form, form)
          |> assign(:pending_template_id, default_template_id)
          |> tap(&update_form_component(&1, form: form, pending_template_id: default_template_id))

        {:noreply,
         socket
         |> put_flash(:error, "更新失敗：#{format_changeset_errors(changeset)}")}
    end
  end

  defp save_campaign(socket, :new, campaign_params, default_template_id) do
    admin_id = socket.assigns.current_admin.id

    campaign_params = Map.put(campaign_params, "admin_id", admin_id)

    case Campaigns.create_campaign(campaign_params) do
      {:ok, campaign} ->
        maybe_assign_default_template(campaign, default_template_id)

        {:noreply,
         socket
         |> put_flash(:info, "Campaign created successfully")
         |> push_navigate(to: ~p"/admin/campaigns/#{campaign.id}/preview?reload=1")}

      {:error, %Ecto.Changeset{} = changeset} ->
        form = to_form(changeset)

        socket =
          socket
          |> assign(:form, form)
          |> assign(:pending_template_id, default_template_id)
          |> tap(&update_form_component(&1, form: form, pending_template_id: default_template_id))

        {:noreply,
         socket
         |> put_flash(:error, "建立失敗：#{format_changeset_errors(changeset)}")}
    end
  end

  defp handle_image_upload(campaign_params, socket) do
    latest_url = socket.assigns[:latest_background_image_url]
    field_value = Map.get(campaign_params, "background_image_url")

    final_params =
      cond do
        is_binary(latest_url) && String.trim(latest_url) != "" ->
          Map.put(campaign_params, "background_image_url", String.trim(latest_url))

        is_binary(field_value) && String.trim(field_value) != "" ->
          campaign_params

        field_value == "" ->
          Map.delete(campaign_params, "background_image_url")

        true ->
          campaign_params
      end

    final_params
  end

  defp upload_in_progress?(socket) do
    case background_upload(socket) do
      nil -> false
      upload -> upload.entries && Enum.any?(upload.entries, &(not &1.done?))
    end
  end

  defp maybe_assign_default_template(_campaign, template_id) when template_id in [nil, ""],
    do: :ok

  defp maybe_assign_default_template(campaign, template_id) do
    Emails.set_campaign_template_default(campaign.id, template_id)
    :ok
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} ->
      field_name = translate_field_name(field)
      "#{field_name}: #{Enum.join(errors, ", ")}"
    end)
    |> Enum.join("；")
  end

  defp translate_field_name(:name), do: "活動名稱"
  defp translate_field_name(:description), do: "描述"
  defp translate_field_name(:starts_at), do: "開始時間"
  defp translate_field_name(:ends_at), do: "結束時間"
  defp translate_field_name(:status), do: "狀態"
  defp translate_field_name(:protection_count), do: "保護數量"
  defp translate_field_name(field), do: to_string(field)

  defp background_upload(socket) do
    with %{uploads: uploads} <- socket.assigns,
         upload when not is_nil(upload) <- Map.get(uploads, :background_image) do
      upload
    else
      _ -> nil
    end
  end

  defp process_background_image_upload(socket) do
    require Logger

    upload = background_upload(socket)

    cond do
      is_nil(upload) ->
        {:error, :upload_not_configured}

      Enum.empty?(upload.entries) ->
        {:error, :no_entries}

      true ->
        uploaded_files =
          consume_uploaded_entries(socket, :background_image, fn %{path: path}, finished_entry ->
            case Dobby.Uploads.ImageProcessor.process_image(path, width: 1920, height: 1080) do
              {:ok, processed_path} ->
                filename = generate_upload_filename(finished_entry.client_name)
                s3_path = "campaigns/backgrounds/#{filename}"

                case Dobby.Uploads.Uploader.upload_file(processed_path, s3_path) do
                  {:ok, url} ->
                    File.rm(processed_path)
                    File.rm(path)
                    {:ok, url}

                  error ->
                    File.rm(processed_path)
                    File.rm(path)
                    error
                end

              {:error, reason} ->
                Logger.warning("Background image processing failed: #{inspect(reason)}")
                filename = generate_upload_filename(finished_entry.client_name)
                s3_path = "campaigns/backgrounds/#{filename}"

                case Dobby.Uploads.Uploader.upload_file(path, s3_path) do
                  {:ok, url} ->
                    File.rm(path)
                    {:ok, url}

                  error ->
                    File.rm(path)
                    error
                end
            end
          end)

        result_url =
          uploaded_files
          |> Enum.find_value(fn
            {:ok, url} -> url
            url when is_binary(url) -> url
            _ -> nil
          end)

        case result_url do
          nil ->
            {:error, :upload_failed}

          url ->
            {:ok, url}
        end
    end
  end

  defp generate_upload_filename(original_name) do
    ext = Path.extname(original_name)
    timestamp = System.system_time(:second)
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "#{timestamp}-#{random}#{ext}"
  end
end
