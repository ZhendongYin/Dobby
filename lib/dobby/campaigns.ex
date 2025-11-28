defmodule Dobby.Campaigns do
  @moduledoc """
  The Campaigns context.
  """

  import Ecto.Query, warn: false
  alias Dobby.Repo
  alias Dobby.Campaigns.Campaign
  alias Dobby.Campaigns.Prize
  alias Dobby.Campaigns.ActivityLog
  alias Dobby.PrizeLibrary
  alias Dobby.Emails
  alias Dobby.Context.Helpers

  # Campaign functions

  @doc """
  Returns the list of campaigns with optional filters.

  Supported filters:
    * `:search` / `"search"` - fuzzy match on name & description
    * `:status` / `"status"` - exact match on status (`"draft"`, `"active"`, `"ended"`, `"disabled"`)
    * `:admin_id` / `"admin_id"` - filter by admin ID (required for security)
    * `:page` / `"page"` - page number (1-based, default: 1)
    * `:page_size` / `"page_size"` - items per page (default: 20)
  """
  def list_campaigns(opts \\ %{}) do
    page = Helpers.fetch_integer_opt(opts, :page) || 1
    page_size = Helpers.fetch_integer_opt(opts, :page_size) || 20
    offset = (page - 1) * page_size
    sort_by = Helpers.fetch_opt(opts, :sort_by) || "inserted_at"
    sort_order = Helpers.fetch_opt(opts, :sort_order) || "desc"
    admin_id = Helpers.fetch_opt(opts, :admin_id)

    query =
      Campaign
      |> maybe_filter_admin_id(admin_id)
      |> maybe_filter_search(Helpers.fetch_opt(opts, :search))
      |> maybe_filter_status(Helpers.fetch_opt(opts, :status))
      |> apply_sort(sort_by, sort_order)

    total = Repo.aggregate(query, :count, :id)

    items =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    %{
      items: items,
      total: total,
      page: page,
      page_size: page_size,
      total_pages: if(page_size > 0, do: ceil(total / page_size), else: 1)
    }
  end

  @doc """
  Gets a single campaign.
  """
  def get_campaign!(id), do: Repo.get!(Campaign, id)

  @doc """
  Gets a single campaign for a specific admin. Raises Ecto.NoResultsError if not found or not owned by admin.
  """
  def get_campaign_for_admin!(id, admin_id) do
    from(c in Campaign,
      where: c.id == ^id and c.admin_id == ^admin_id
    )
    |> Repo.one!()
  end

  @doc """
  Verifies if a campaign is owned by the given admin.
  Returns true if owned, false otherwise.
  """
  def verify_campaign_ownership(campaign_id, admin_id) do
    case Repo.one(
           from(c in Campaign,
             where: c.id == ^campaign_id and c.admin_id == ^admin_id,
             select: count(c.id)
           )
         ) do
      1 -> true
      _ -> false
    end
  end

  @doc """
  Verifies if a prize's campaign is owned by the given admin.
  Returns true if owned, false otherwise.
  """
  def verify_prize_ownership(prize_id, admin_id) do
    case Repo.one(
           from(p in Prize,
             join: c in assoc(p, :campaign),
             where: p.id == ^prize_id and c.admin_id == ^admin_id,
             select: count(p.id)
           )
         ) do
      1 -> true
      _ -> false
    end
  end

  @doc """
  Creates a campaign.
  """
  def create_campaign(attrs \\ %{}) do
    {template_id, attrs} = pop_template_id(attrs)

    %Campaign{}
    |> Campaign.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, campaign} ->
        maybe_assign_default_template(campaign, template_id)
        {:ok, campaign}

      error ->
        error
    end
  end

  @doc """
  Updates a campaign.
  """
  def update_campaign(%Campaign{} = campaign, attrs, opts \\ []) do
    {template_id, attrs} = pop_template_id(attrs)
    changeset = Campaign.changeset(campaign, attrs)
    admin_id = Keyword.get(opts, :admin_id)

    # Log changes before update (changeset.data contains original values)
    log_campaign_update(campaign, changeset, admin_id)

    case Repo.update(changeset) do
      {:ok, updated_campaign} ->
        maybe_assign_default_template(updated_campaign, template_id)
        {:ok, updated_campaign}

      error ->
        error
    end
  end

  @doc """
  Deletes a campaign.
  """
  def delete_campaign(%Campaign{} = campaign) do
    Repo.delete(campaign)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking campaign changes.
  """
  def change_campaign(%Campaign{} = campaign, attrs \\ %{}) do
    Campaign.changeset(campaign, attrs)
  end

  # Prize functions

  @doc """
  Returns the list of prizes for a campaign.

  Supported opts:
    * `:page` / `"page"` - page number (1-based, default: 1)
    * `:page_size` / `"page_size"` - items per page (default: 20)
  """
  def list_prizes(campaign_id, opts \\ %{}) do
    page = Helpers.fetch_integer_opt(opts, :page) || 1
    page_size = Helpers.fetch_integer_opt(opts, :page_size) || 20
    offset = (page - 1) * page_size

    query =
      from(p in Prize,
        where: p.campaign_id == ^campaign_id,
        order_by: [asc: p.display_order, asc: p.inserted_at]
      )

    total = Repo.aggregate(query, :count, :id)

    items =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> preload([:source_template, :email_template])
      |> Repo.all()

    %{
      items: items,
      total: total,
      page: page,
      page_size: page_size,
      total_pages: if(page_size > 0, do: ceil(total / page_size), else: 1)
    }
  end

  @doc """
  Returns all prizes across campaigns with optional filters.
  Supported filters: :search, :type (physical|virtual|no_prize|all)
  """
  def list_all_prizes(filters \\ %{}) do
    from(p in Prize,
      left_join: c in assoc(p, :campaign),
      preload: [campaign: c, source_template: [], email_template: []],
      order_by: [desc: p.inserted_at]
    )
    |> apply_prize_filters(filters)
    |> Repo.all()
  end

  @doc """
  Gets a single prize.
  """
  def get_prize!(id) do
    Prize
    |> Repo.get!(id)
    |> Repo.preload([:source_template, :email_template])
  end

  @doc """
  Creates a prize.
  """
  def create_prize(attrs \\ %{}, opts \\ []) do
    admin_id = Keyword.get(opts, :admin_id)

    case %Prize{}
         |> Prize.changeset(attrs)
         |> Repo.insert() do
      {:ok, prize} ->
        log_prize_create(prize, admin_id)
        {:ok, prize}

      error ->
        error
    end
  end

  @doc """
  Clone a prize template into the given campaign with overrides.
  """
  def create_prize_from_template(template_id, campaign_id, overrides \\ %{}) do
    template = PrizeLibrary.get_template!(template_id)

    attrs =
      template
      |> template_to_prize_attrs()
      |> Map.merge(%{
        "campaign_id" => campaign_id,
        "source_template_id" => template.id
      })
      |> Map.merge(overrides)

    create_prize(attrs)
  end

  @doc """
  Updates a prize.
  """
  def update_prize(%Prize{} = prize, attrs, opts \\ []) do
    changeset = Prize.changeset(prize, attrs)
    admin_id = Keyword.get(opts, :admin_id)

    # Log changes before update (use original prize struct for old values)
    log_prize_update(prize, changeset, admin_id)

    case Repo.update(changeset) do
      {:ok, updated_prize} ->
        {:ok, updated_prize}

      error ->
        error
    end
  end

  @doc """
  Deletes a prize.
  """
  def delete_prize(%Prize{} = prize, opts \\ []) do
    admin_id = Keyword.get(opts, :admin_id)
    campaign_id = prize.campaign_id
    prize_name = Prize.get_name(prize) || "未知獎品"

    case Repo.delete(prize) do
      {:ok, _deleted_prize} ->
        log_prize_delete(campaign_id, prize.id, prize_name, admin_id)
        {:ok, :deleted}

      error ->
        error
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking prize changes.
  """
  def change_prize(%Prize{} = prize, attrs \\ %{}) do
    Prize.changeset(prize, attrs)
  end

  @doc """
  Returns the list of prizes that use a specific template.
  """
  def list_prizes_by_template(template_id) do
    from(p in Prize,
      where: p.source_template_id == ^template_id,
      preload: [:source_template, :email_template]
    )
    |> Repo.all()
  end

  @doc """
  Syncs template data to all prizes that use this template.
  由于模板字段不再存储在 prize 表中，此函数现在只需要确保 source_template_id 正确设置
  """
  def sync_template_to_prizes(template_id, _template_attrs) do
    # 模板字段现在直接从模板读取，不需要更新 prize 表
    # 只需要确保所有使用该模板的 prize 都有正确的 source_template_id
    prizes = list_prizes_by_template(template_id)

    # 确保所有 prize 都有 source_template_id（应该已经有了，但为了安全起见检查一下）
    Enum.each(prizes, fn prize ->
      if !prize.source_template_id do
        update_prize(prize, %{"source_template_id" => template_id})
      end
    end)

    {:ok, length(prizes)}
  end

  defp maybe_filter_search(query, value)

  defp maybe_filter_search(query, nil), do: query

  defp maybe_filter_search(query, value) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      query
    else
      escaped = Helpers.escape_like(String.downcase(trimmed))
      term = "%#{escaped}%"

      from c in query,
        where:
          ilike(c.name, ^term) or
            ilike(fragment("coalesce(?, '')", c.description), ^term)
    end
  end

  defp maybe_filter_search(query, _value), do: query

  defp maybe_filter_status(query, value)

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, "all"), do: query

  defp maybe_filter_status(query, value) do
    from c in query, where: c.status == ^value
  end

  defp maybe_filter_admin_id(query, nil), do: query

  defp maybe_filter_admin_id(query, admin_id) when not is_nil(admin_id) do
    where(query, [c], c.admin_id == ^admin_id)
  end

  defp apply_sort(query, field, order) do
    direction = if order == "desc", do: :desc, else: :asc

    case field do
      "name" -> order_by(query, [c], [{^direction, c.name}])
      "status" -> order_by(query, [c], [{^direction, c.status}])
      "starts_at" -> order_by(query, [c], [{^direction, c.starts_at}])
      "ends_at" -> order_by(query, [c], [{^direction, c.ends_at}])
      "inserted_at" -> order_by(query, [c], [{^direction, c.inserted_at}])
      "updated_at" -> order_by(query, [c], [{^direction, c.updated_at}])
      # default
      _ -> order_by(query, [c], [{^direction, c.inserted_at}])
    end
  end

  defp template_to_prize_attrs(template) do
    %{
      "name" => template.name,
      "prize_type" => template.prize_type,
      "image_url" => template.image_url,
      "description" => template.description,
      "redemption_guide" => template.redemption_guide
    }
  end

  defp pop_template_id(attrs) do
    case Map.pop(attrs, "default_template_id") do
      {nil, attrs} -> Map.pop(attrs, :default_template_id)
      result -> result
    end
  end

  defp maybe_assign_default_template(_campaign, template_id) when template_id in [nil, ""],
    do: :ok

  defp maybe_assign_default_template(campaign, template_id) do
    Emails.set_campaign_template_default(campaign.id, template_id)
    :ok
  end

  defp apply_prize_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:search, ""}, query ->
        query

      {:search, nil}, query ->
        query

      {:search, search}, query ->
        escaped = Helpers.escape_like(String.downcase(search))
        term = "%#{escaped}%"

        from [p, c] in query,
          where:
            ilike(p.name, ^term) or
              ilike(fragment("coalesce(?, '')", p.description), ^term) or
              ilike(fragment("coalesce(?, '')", c.name), ^term)

      {:type, "all"}, query ->
        query

      {:type, type}, query ->
        from p in query, where: p.prize_type == ^type

      _, query ->
        query
    end)
  end

  @doc """
  Resets daily_used to 0 for all prizes that have a daily_limit > 0.
  This function is called daily by the scheduler.
  """
  def reset_all_prizes_daily_usage do
    from(p in Prize,
      where: not is_nil(p.daily_limit) and p.daily_limit > 0
    )
    |> Repo.update_all(set: [daily_used: 0])
  end

  @doc """
  Updates campaign statuses based on their start and end dates.
  This function is called periodically by the scheduler.

  Rules:
  - If current time >= starts_at and status is "draft", set to "active"
  - If current time > ends_at and status is "active", set to "ended"
  - "disabled" status is not changed (manually disabled campaigns)
  """
  def update_campaign_statuses do
    now = DateTime.utc_now()

    # Find campaigns that should be activated
    # (starts_at is required, so we don't need to check for nil)
    from(c in Campaign,
      where: c.status == "draft" and not is_nil(c.starts_at) and c.starts_at <= ^now
    )
    |> Repo.update_all(set: [status: "active"])

    # Find campaigns that should be ended
    # (ends_at is required, so we don't need to check for nil)
    from(c in Campaign,
      where: c.status == "active" and not is_nil(c.ends_at) and c.ends_at < ^now
    )
    |> Repo.update_all(set: [status: "ended"])

    :ok
  end

  # Activity Log functions

  @doc """
  Returns the list of activity logs for a campaign.
  """
  def list_activity_logs(campaign_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    ActivityLog
    |> where([al], al.campaign_id == ^campaign_id)
    |> order_by([al], desc: al.inserted_at)
    |> limit(^limit)
    |> preload([:admin])
    |> Repo.all()
  end

  defp log_campaign_update(campaign, changeset, admin_id) do
    changes = changeset.changes
    campaign_id = campaign.id

    # Log each changed field
    Enum.each(changes, fn {field, new_value} ->
      # Get old value directly from the original campaign struct
      old_value = Map.get(campaign, field)

      # Skip if values are the same or field is admin_id
      if field != :admin_id && old_value != new_value do
        log_activity(%{
          campaign_id: campaign_id,
          admin_id: admin_id,
          action: "update_campaign",
          target_type: "campaign",
          target_id: campaign_id,
          field: Atom.to_string(field),
          from_value: format_value(old_value),
          to_value: format_value(new_value)
        })
      end
    end)
  end

  defp log_prize_create(prize, admin_id) do
    prize_name = Prize.get_name(prize) || "未知獎品"

    log_activity(%{
      campaign_id: prize.campaign_id,
      admin_id: admin_id,
      action: "create_prize",
      target_type: "prize",
      target_id: prize.id,
      metadata: %{
        prize_name: prize_name,
        prize_type: prize.prize_type || Prize.get_prize_type(prize)
      }
    })
  end

  defp log_prize_update(prize, changeset, admin_id) do
    changes = changeset.changes
    campaign_id = prize.campaign_id
    prize_id = prize.id

    # Log each changed field
    Enum.each(changes, fn {field, new_value} ->
      # Get old value directly from the original prize struct
      old_value = Map.get(prize, field)

      # Skip if values are the same or field is campaign_id
      if field != :campaign_id && old_value != new_value do
        log_activity(%{
          campaign_id: campaign_id,
          admin_id: admin_id,
          action: "update_prize",
          target_type: "prize",
          target_id: prize_id,
          field: Atom.to_string(field),
          from_value: format_value(old_value),
          to_value: format_value(new_value),
          metadata: %{
            prize_name: Prize.get_name(prize) || "未知獎品"
          }
        })
      end
    end)
  end

  defp log_prize_delete(campaign_id, prize_id, prize_name, admin_id) do
    log_activity(%{
      campaign_id: campaign_id,
      admin_id: admin_id,
      action: "delete_prize",
      target_type: "prize",
      target_id: prize_id,
      metadata: %{
        prize_name: prize_name
      }
    })
  end

  defp log_activity(attrs) do
    %ActivityLog{}
    |> ActivityLog.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _log} -> :ok
      # Silently fail to not break main flow
      {:error, _changeset} -> :ok
    end
  end

  defp format_value(value) when is_nil(value), do: nil
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_value(value) when is_float(value), do: Float.to_string(value)
  defp format_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_value(%Date{} = d), do: Date.to_iso8601(d)
  defp format_value(value) when is_boolean(value), do: to_string(value)
  defp format_value(value), do: inspect(value)
end
