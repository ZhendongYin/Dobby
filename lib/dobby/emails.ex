defmodule Dobby.Emails do
  @moduledoc """
  The Emails context.
  """

  import Ecto.Query, warn: false
  alias Dobby.Repo
  alias Dobby.Campaigns
  alias Dobby.Campaigns.Prize, as: CampaignPrize
  alias Dobby.Emails.{CampaignEmailTemplate, EmailTemplate, EmailLog}
  alias Dobby.Context.Helpers
  alias Dobby.Mailer
  alias Dobby.Lottery.WinningRecord
  alias Swoosh.Email

  @public_blueprints [
    %{
      key: "celebration_tw",
      label: "經典慶祝通知",
      description: "繁體中文稿件、包含 CTA 與獎品資訊，適合多數行銷活動。",
      theme: "sunset"
    }
  ]

  @doc """
  Returns the list of global email_templates (not tied to a specific campaign).
  """
  def list_global_templates(filters \\ %{}) do
    page = Helpers.fetch_integer_opt(filters, :page) || 1
    page_size = Helpers.fetch_integer_opt(filters, :page_size) || 20
    offset = (page - 1) * page_size
    sort_by = Helpers.fetch_opt(filters, :sort_by) || "inserted_at"
    sort_order = Helpers.fetch_opt(filters, :sort_order) || "desc"

    query =
      EmailTemplate
      |> template_filters(filters)
      |> apply_email_template_sort(sort_by, sort_order)

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
  Returns the list of email_templates for a campaign (legacy, for backward compatibility).
  """
  def list_email_templates(campaign_id) do
    CampaignEmailTemplate
    |> where([cet], cet.campaign_id == ^campaign_id)
    |> join(:inner, [cet], et in assoc(cet, :email_template))
    |> preload([cet, et], email_template: et)
    |> order_by([cet], desc: cet.is_default, desc: cet.inserted_at)
    |> Repo.all()
    |> Enum.map(&decorate_assignment/1)
  end

  defp template_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:search, term}, query when is_binary(term) and term != "" ->
        escaped = Helpers.escape_like(String.downcase(term))
        like = "%#{escaped}%"

        from et in query,
          where:
            ilike(et.name, ^like) or
              ilike(fragment("coalesce(?, '')", et.subject), ^like)

      _, query ->
        query
    end)
  end

  @doc """
  Gets a single email_template.
  """
  def get_email_template!(id), do: Repo.get!(EmailTemplate, id)

  def get_campaign_template!(campaign_id, template_id) do
    CampaignEmailTemplate
    |> where([cet], cet.campaign_id == ^campaign_id and cet.email_template_id == ^template_id)
    |> join(:inner, [cet], et in assoc(cet, :email_template))
    |> preload([cet, et], email_template: et)
    |> Repo.one!()
    |> decorate_assignment()
  end

  @doc """
  Gets the primary email template for a campaign (default assignment or first available).
  """
  def get_campaign_email_template(%Campaigns.Campaign{} = campaign) do
    get_default_email_template(campaign.id) ||
      campaign.id
      |> list_email_templates()
      |> List.first()
  end

  @doc """
  Gets the default email template for a campaign (legacy).
  """
  def get_default_email_template(campaign_id) do
    CampaignEmailTemplate
    |> where([cet], cet.campaign_id == ^campaign_id and cet.is_default == true)
    |> join(:inner, [cet], et in assoc(cet, :email_template))
    |> preload([cet, et], email_template: et)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      assignment -> decorate_assignment(assignment)
    end
  end

  @doc """
  Creates an email_template.
  """
  def create_email_template(attrs \\ %{}) do
    {campaign_id, attrs} = pop_campaign_id(attrs)
    {is_default, attrs} = pop_is_default(attrs)

    %EmailTemplate{}
    |> EmailTemplate.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, template} ->
        {:ok, _assignment} =
          maybe_assign_template_to_campaign(template, campaign_id, is_default)

        {:ok, template}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Updates an email_template.
  """
  def update_email_template(%EmailTemplate{} = email_template, attrs) do
    {_is_default, attrs} = pop_is_default(attrs)

    email_template
    |> EmailTemplate.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an email_template.
  """
  def delete_email_template(%EmailTemplate{} = email_template) do
    Repo.delete(email_template)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking email_template changes.
  """
  def change_email_template(%EmailTemplate{} = email_template, attrs \\ %{}) do
    EmailTemplate.changeset(email_template, attrs)
  end

  @doc """
  Creates a new template scoped to the given campaign (and assigns it).
  """
  def create_campaign_template(%Campaigns.Campaign{} = campaign, attrs) do
    attrs =
      attrs
      |> Map.put("campaign_id", campaign.id)

    create_email_template(attrs)
  end

  @doc """
  Updates a template within the context of a campaign (allowing default toggle).
  """
  def update_campaign_template(
        %Campaigns.Campaign{} = campaign,
        %EmailTemplate{} = template,
        attrs
      ) do
    {is_default, attrs} = pop_is_default(attrs)

    case update_email_template(template, attrs) do
      {:ok, template} ->
        update_assignment_default(campaign.id, template.id, is_default)
        {:ok, template}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Assigns an existing template from the global library to a campaign.
  """
  def assign_template_to_campaign(%Campaigns.Campaign{} = campaign, template_id, opts \\ []) do
    is_default = truthy?(Keyword.get(opts, :is_default, false))

    attrs = %{
      campaign_id: campaign.id,
      email_template_id: template_id,
      is_default: is_default
    }

    %CampaignEmailTemplate{}
    |> CampaignEmailTemplate.changeset(attrs)
    |> Repo.insert(
      on_conflict: [set: [is_default: is_default, updated_at: DateTime.utc_now()]],
      conflict_target: [:campaign_id, :email_template_id],
      returning: true
    )
    |> case do
      {:ok, assignment} ->
        if is_default do
          unset_other_defaults(campaign.id, template_id)
        end

        {:ok, assignment}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Removes the association between a campaign and a template.
  """
  def unassign_template_from_campaign(%Campaigns.Campaign{} = campaign, template_id) do
    Repo.transaction(fn ->
      Repo.delete_all(
        from cet in CampaignEmailTemplate,
          where: cet.campaign_id == ^campaign.id and cet.email_template_id == ^template_id
      )

      ensure_default_assignment(campaign.id)
    end)
  end

  @doc """
  Marks the given template as the default for a campaign.
  """
  def set_campaign_template_default(campaign_id, template_id) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()

      {count, _} =
        Repo.update_all(
          from(cet in CampaignEmailTemplate,
            where: cet.campaign_id == ^campaign_id and cet.email_template_id == ^template_id
          ),
          set: [is_default: true, updated_at: now]
        )

      unset_other_defaults(campaign_id, template_id)

      assignment =
        if count == 0 do
          campaign = Campaigns.get_campaign!(campaign_id)
          {:ok, assignment} = assign_template_to_campaign(campaign, template_id, is_default: true)
          assignment
        else
          get_assignment(campaign_id, template_id)
        end

      decorate_assignment(assignment)
    end)
  end

  defp update_assignment_default(campaign_id, template_id, is_default) do
    if truthy?(is_default) do
      set_campaign_template_default(campaign_id, template_id)
    else
      now = DateTime.utc_now()

      Repo.update_all(
        from(cet in CampaignEmailTemplate,
          where: cet.campaign_id == ^campaign_id and cet.email_template_id == ^template_id
        ),
        set: [is_default: false, updated_at: now]
      )

      ensure_default_assignment(campaign_id)
      :ok
    end
  end

  defp ensure_default_assignment(campaign_id) do
    has_default? =
      CampaignEmailTemplate
      |> where([cet], cet.campaign_id == ^campaign_id and cet.is_default == true)
      |> select([cet], 1)
      |> limit(1)
      |> Repo.one()
      |> is_nil()
      |> Kernel.not()

    cond do
      has_default? ->
        :ok

      assignment =
          CampaignEmailTemplate
          |> where([cet], cet.campaign_id == ^campaign_id)
          |> order_by([cet], desc: cet.inserted_at)
          |> limit(1)
          |> Repo.one() ->
        Repo.update_all(
          from(cet in CampaignEmailTemplate, where: cet.id == ^assignment.id),
          set: [is_default: true, updated_at: DateTime.utc_now()]
        )

        :ok

      true ->
        :ok
    end
  end

  defp unset_other_defaults(campaign_id, template_id) do
    Repo.update_all(
      from(cet in CampaignEmailTemplate,
        where:
          cet.campaign_id == ^campaign_id and cet.email_template_id != ^template_id and
            cet.is_default == true
      ),
      set: [is_default: false, updated_at: DateTime.utc_now()]
    )
  end

  defp decorate_assignment(%CampaignEmailTemplate{} = assignment) do
    assignment.email_template
    |> Map.put(:campaign_assignment, assignment)
    |> Map.put(:is_default, assignment.is_default)
  end

  defp get_assignment(campaign_id, template_id) do
    CampaignEmailTemplate
    |> where([cet], cet.campaign_id == ^campaign_id and cet.email_template_id == ^template_id)
    |> join(:inner, [cet], et in assoc(cet, :email_template))
    |> preload([cet, et], email_template: et)
    |> Repo.one()
  end

  defp maybe_assign_template_to_campaign(_template, nil, _is_default), do: {:ok, nil}

  defp maybe_assign_template_to_campaign(template, campaign_id, is_default) do
    campaign = Campaigns.get_campaign!(campaign_id)
    assign_template_to_campaign(campaign, template.id, is_default: is_default)
  end

  defp pop_campaign_id(attrs) do
    {value, attrs} = Map.pop(attrs, "campaign_id")

    if value do
      {value, attrs}
    else
      Map.pop(attrs, :campaign_id)
    end
  end

  defp pop_is_default(attrs) do
    {value, attrs} = Map.pop(attrs, "is_default")

    cond do
      not is_nil(value) ->
        {normalize_boolean(value), attrs}

      true ->
        {value2, attrs} = Map.pop(attrs, :is_default)
        {normalize_boolean(value2), attrs}
    end
  end

  defp normalize_boolean(value) when value in [true, false], do: value

  defp normalize_boolean(value) when is_binary(value),
    do: String.downcase(value) in ["true", "1", "on"]

  defp normalize_boolean(_), do: false

  defp truthy?(value), do: normalize_boolean(value)

  @doc """
  Lists available public template blueprints that admins can instantiate quickly.
  """
  def public_blueprints, do: @public_blueprints

  @doc """
  Ensures there is always at least one default template for the given campaign.
  Returns the default template that is guaranteed to exist afterwards.
  """
  def ensure_default_template!(%Campaigns.Campaign{} = campaign) do
    case get_default_email_template(campaign.id) do
      nil ->
        assignments =
          CampaignEmailTemplate
          |> where([cet], cet.campaign_id == ^campaign.id)
          |> join(:inner, [cet], et in assoc(cet, :email_template))
          |> preload([cet, et], email_template: et)
          |> order_by([cet], desc: cet.inserted_at)
          |> Repo.all()

        cond do
          assignments == [] ->
            {:ok, template} =
              campaign
              |> build_blueprint_attrs("celebration_tw", default?: true)
              |> create_email_template()

            template

          true ->
            assignment = hd(assignments)

            {:ok, template} =
              set_campaign_template_default(campaign.id, assignment.email_template_id)

            template
        end

      template ->
        template
    end
  end

  @doc """
  Creates an email template from a predefined public blueprint.
  """
  def create_from_blueprint(%Campaigns.Campaign{} = campaign, blueprint_key, opts \\ []) do
    campaign
    |> build_blueprint_attrs(blueprint_key, opts)
    |> create_email_template()
  end

  defp build_blueprint_attrs(%Campaigns.Campaign{} = campaign, nil, opts) do
    build_blueprint_attrs(campaign, "celebration_tw", opts)
  end

  defp build_blueprint_attrs(%Campaigns.Campaign{} = campaign, key, opts) do
    prizes = Campaigns.list_prizes(campaign.id)

    # Ensure prizes is a list, not a paginated result
    prize_list =
      if is_list(prizes) do
        prizes
      else
        Map.get(prizes, :items, [])
      end

    showcase_prize =
      prize_list
      |> Enum.reject(&(&1.prize_type == "no_prize"))
      |> List.first()

    data = template_data(campaign, showcase_prize)

    case key do
      "celebration_tw" ->
        %{
          campaign_id: campaign.id,
          name: opts[:name] || "經典慶祝通知",
          subject: "#{campaign.name}｜恭喜中獎通知",
          html_content: celebration_html(data),
          text_content: celebration_text(data),
          variables: data,
          is_default: Keyword.get(opts, :default?, false)
        }

      _ ->
        build_blueprint_attrs(campaign, "celebration_tw", opts)
    end
  end

  defp template_data(campaign, prize) do
    %{
      "campaign_name" => campaign.name,
      "campaign_theme_color" => campaign.theme_color || "#4338ca",
      "prize_name" => (prize && prize.name) || "神秘好禮",
      "prize_description" => (prize && prize.description) || "專屬於您的限量獎品",
      "prize_image_url" =>
        cond do
          prize && prize.image_url ->
            prize.image_url

          campaign.background_image_url ->
            campaign.background_image_url

          true ->
            "https://images.unsplash.com/photo-1525182008055-f88b95ff7980?auto=format&fit=crop&w=900&q=60"
        end,
      "redemption_guide" =>
        (prize && prize.redemption_guide) ||
          campaign.rules_text ||
          "請於 7 天內回覆此信件並提供必要的寄送資訊，我們將為您安排獎品發放。",
      "support_email" => "support@dobby.app"
    }
  end

  defp celebration_html(data) do
    """
    <!doctype html>
    <html lang="zh-Hant">
      <head>
        <meta charset="utf-8" />
        <title>#{data["campaign_name"]}｜恭喜中獎通知</title>
      </head>
      <body style="margin:0;padding:0;background-color:#f8fafc;font-family:'Noto Sans TC','Inter',sans-serif;">
        <table width="100%" cellpadding="0" cellspacing="0" role="presentation" style="background-color:#f8fafc;padding:32px 0;">
          <tr>
            <td align="center">
              <table width="600" cellpadding="0" cellspacing="0" role="presentation" style="background:#ffffff;border-radius:24px;overflow:hidden;box-shadow:0 20px 45px rgba(15,23,42,0.08);">
                <tr>
                  <td style="background:linear-gradient(120deg, #{data["campaign_theme_color"]}, #f97316);padding:48px 40px 32px 40px;color:#fff;text-align:left;">
                    <p style="margin:0;font-size:14px;letter-spacing:0.3em;text-transform:uppercase;opacity:0.9;">#{data["campaign_name"]}</p>
                    <h1 style="margin:12px 0 16px 0;font-size:32px;line-height:1.3;font-weight:700;">🎉 恭喜您中獎！</h1>
                    <p style="margin:0;font-size:16px;line-height:1.8;opacity:0.95;">
                      感謝參與，我們非常榮幸地通知您，已於本次活動中抽中
                      <strong style="color:#fff;">#{data["prize_name"]}</strong>。
                    </p>
                  </td>
                </tr>
                <tr>
                  <td style="padding:36px 40px 16px 40px;">
                    <div style="border:1px solid #e2e8f0;border-radius:20px;overflow:hidden;">
                      <img src="#{data["prize_image_url"]}" alt="#{data["prize_name"]}" style="width:100%;height:260px;object-fit:cover;display:block;" />
                      <div style="padding:24px;">
                        <p style="margin:0;font-size:14px;letter-spacing:0.2em;text-transform:uppercase;color:#475569;">獎品資訊</p>
                        <h2 style="margin:12px 0;font-size:24px;color:#0f172a;">#{data["prize_name"]}</h2>
                        <p style="margin:0;font-size:16px;line-height:1.7;color:#475569;">#{data["prize_description"]}</p>
                      </div>
                    </div>
                  </td>
                </tr>
                <tr>
                  <td style="padding:0 40px 32px 40px;">
                    <div style="background:#0f172a;border-radius:20px;padding:28px;color:#f8fafc;">
                      <h3 style="margin:0 0 12px 0;font-size:18px;letter-spacing:0.04em;">如何領取獎品</h3>
                      <p style="margin:0;font-size:15px;line-height:1.8;">#{data["redemption_guide"]}</p>
                    </div>
                  </td>
                </tr>
                <tr>
                  <td style="padding:0 40px 48px 40px;text-align:center;">
                    <a href="mailto:#{data["support_email"]}?subject=#{URI.encode("回覆：#{data["campaign_name"]} 中獎通知")}" style="display:inline-block;padding:14px 32px;border-radius:999px;background:linear-gradient(120deg, #{data["campaign_theme_color"]}, #f97316);color:#fff;text-decoration:none;font-weight:600;box-shadow:0 10px 25px rgba(249,115,22,0.35);">
                      立即回覆並完成領取
                    </a>
                    <p style="margin:16px 0 0 0;font-size:13px;color:#64748b;">
                      若您有任何問題，歡迎隨時來信 <a href="mailto:#{data["support_email"]}" style="color:#{data["campaign_theme_color"]};text-decoration:none;">#{data["support_email"]}</a>
                    </p>
                  </td>
                </tr>
              </table>
              <p style="margin-top:24px;font-size:12px;color:#94a3b8;">
                此信件由系統自動發出，請勿直接回覆。
              </p>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  defp celebration_text(data) do
    """
    【#{data["campaign_name"]}｜恭喜中獎通知】

    親愛的用戶您好：

    感謝您參與本次活動，恭喜獲得「#{data["prize_name"]}」！

    #{data["redemption_guide"]}

    若需協助，請回覆此信件或來信 #{data["support_email"]}，我們會盡快與您聯繫。

    #{data["campaign_name"]} 團隊
    """
    |> String.trim()
  end

  @doc """
  Sends a winning notification email to the user.

  This function:
  1. Gets the email template (default or specified)
  2. Replaces template variables with actual data
  3. Sends the email using Swoosh
  4. Updates the winning record with email_sent status
  """
  def send_winning_notification(%WinningRecord{} = winning_record) do
    require Logger

    winning_record =
      Repo.preload(winning_record,
        prize: [:email_template, :source_template],
        campaign: [],
        transaction_number: []
      )

    campaign = winning_record.campaign
    prize = winning_record.prize

    # Get email template (from campaign association or fallback)
    template =
      prize.email_template ||
        get_campaign_email_template(campaign) ||
        ensure_default_template!(campaign)

    # Build variable data
    variables = build_winning_variables(winning_record, prize, campaign)

    # Replace variables in template content
    subject = replace_variables(template.subject, variables)
    html_content = replace_variables(template.html_content, variables)
    text_content = replace_variables(template.text_content || "", variables)

    # Build email
    email =
      Email.new()
      |> Email.to(winning_record.email)
      |> Email.from({"#{campaign.name} 團隊", get_from_email()})
      |> Email.subject(subject)
      |> Email.html_body(html_content)
      |> Email.text_body(text_content)

    # 创建邮件日志记录（pending 状态）
    email_log =
      create_email_log(%{
        winning_record_id: winning_record.id,
        campaign_id: campaign.id,
        email_template_id: template.id,
        to_email: winning_record.email,
        from_email: get_from_email(),
        from_name: "#{campaign.name} 團隊",
        subject: subject,
        html_content: html_content,
        text_content: text_content,
        status: "pending",
        metadata: %{
          variables: variables,
          prize_name: CampaignPrize.get_name(prize),
          campaign_name: campaign.name
        }
      })

    # Send email
    case Mailer.deliver(email) do
      {:ok, _} ->
        # 更新日志为成功
        update_email_log_status(email_log, "sent", DateTime.utc_now())

        # Update winning record
        now = DateTime.utc_now()

        winning_record
        |> Ecto.Changeset.change(%{
          email_sent: true,
          email_sent_at: now
        })
        |> Repo.update()

        Logger.info(
          "Winning notification email sent to #{winning_record.email} for record #{winning_record.id}"
        )

        {:ok, winning_record}

      {:error, reason} ->
        # 更新日志为失败
        error_msg = inspect(reason)
        update_email_log_status(email_log, "failed", nil, error_msg)

        Logger.error("Failed to send winning notification email: #{error_msg}")
        {:error, reason}
    end
  end

  @doc """
  Resends a winning notification email.
  """
  def resend_winning_notification(%WinningRecord{} = winning_record) do
    send_winning_notification(winning_record)
  end

  defp build_winning_variables(winning_record, prize, campaign) do
    %{
      "user_name" => winning_record.name || "親愛的用戶",
      "prize_name" => CampaignPrize.get_name(prize) || "獎品",
      "prize_description" => CampaignPrize.get_description(prize) || "",
      "prize_image_url" =>
        CampaignPrize.get_image_url(prize) ||
          campaign.background_image_url ||
          "https://images.unsplash.com/photo-1525182008055-f88b95ff7980?auto=format&fit=crop&w=900&q=60",
      "campaign_name" => campaign.name,
      "campaign_theme_color" => campaign.theme_color || "#4338ca",
      "redemption_guide" =>
        CampaignPrize.get_redemption_guide(prize) ||
          campaign.rules_text ||
          "請於 7 天內回覆此信件並提供必要的寄送資訊，我們將為您安排獎品發放。",
      "virtual_code" => winning_record.virtual_code || "",
      "transaction_number" =>
        (winning_record.transaction_number && winning_record.transaction_number.transaction_number) ||
          "",
      "support_email" => get_support_email(),
      "expiry_date" => format_expiry_date(winning_record.inserted_at)
    }
  end

  defp replace_variables(content, variables) when is_binary(content) do
    Enum.reduce(variables, content, fn {key, value}, acc ->
      # Replace {key} and {{key}} patterns
      pattern = ~r/\{#{Regex.escape(key)}\}|\{\{#{Regex.escape(key)}\}\}/
      String.replace(acc, pattern, to_string(value))
    end)
  end

  defp replace_variables(nil, _variables), do: ""

  defp get_from_email do
    Application.get_env(:dobby, :from_email, "noreply@dobby.app")
  end

  defp get_support_email do
    Application.get_env(:dobby, :support_email, "support@dobby.app")
  end

  defp format_expiry_date(nil), do: "7 天內"

  defp format_expiry_date(inserted_at) do
    expiry_date = DateTime.add(inserted_at, 7, :day)
    Calendar.strftime(expiry_date, "%Y 年 %m 月 %d 日")
  end

  @doc """
  Get email statistics for a campaign.
  """
  def get_email_stats(campaign_id) do
    import Ecto.Query

    total_sent =
      from(wr in WinningRecord,
        where: wr.campaign_id == ^campaign_id and wr.email_sent == true
      )
      |> Repo.aggregate(:count)

    total_with_email =
      from(wr in WinningRecord,
        where: wr.campaign_id == ^campaign_id and not is_nil(wr.email)
      )
      |> Repo.aggregate(:count)

    sent_today =
      today = DateTime.utc_now() |> DateTime.to_date()

    from(wr in WinningRecord,
      where:
        wr.campaign_id == ^campaign_id and
          wr.email_sent == true and
          fragment("DATE(?)", wr.email_sent_at) == ^today
    )
    |> Repo.aggregate(:count)

    success_rate =
      if total_with_email > 0 do
        Float.round(total_sent / total_with_email * 100, 1)
      else
        0.0
      end

    %{
      total_sent: total_sent,
      total_with_email: total_with_email,
      sent_today: sent_today,
      success_rate: success_rate,
      pending: total_with_email - total_sent
    }
  end

  # Email Log functions

  @doc """
  Returns the list of all email logs with optional filters.

  Supported opts:
    * `:page` - page number (1-based, default: 1)
    * `:page_size` - items per page (default: 20)
    * `:status` - filter by status
    * `:campaign_id` - filter by campaign
    * `:search` - search term
  """
  def list_all_email_logs(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, Keyword.get(opts, :limit, 20))
    offset = (page - 1) * page_size
    sort_by = Keyword.get(opts, :sort_by, "inserted_at")
    sort_order = Keyword.get(opts, :sort_order, "desc")

    status = Keyword.get(opts, :status)
    campaign_id = Keyword.get(opts, :campaign_id)
    search = Keyword.get(opts, :search)

    query =
      EmailLog
      |> maybe_filter_status(status)
      |> maybe_filter_campaign(campaign_id)
      |> maybe_filter_search(search)
      |> apply_email_log_sort(sort_by, sort_order)

    total = Repo.aggregate(query, :count, :id)

    items =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> preload([:campaign, :winning_record, :email_template])
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
  Gets a single email log.
  """
  def get_email_log!(id) do
    EmailLog
    |> Repo.get!(id)
    |> Repo.preload([:winning_record, :email_template, :campaign])
  end

  @doc """
  Get email log statistics.
  """
  def get_email_log_stats(opts \\ []) do
    base_query = EmailLog |> maybe_filter_campaign(Keyword.get(opts, :campaign_id))

    total = Repo.aggregate(base_query, :count, :id)
    sent = Repo.aggregate(where(base_query, [el], el.status == "sent"), :count, :id)
    failed = Repo.aggregate(where(base_query, [el], el.status == "failed"), :count, :id)

    %{total: total, sent: sent, failed: failed}
  end

  defp create_email_log(attrs) do
    %EmailLog{}
    |> EmailLog.changeset(attrs)
    |> Repo.insert!()
  end

  defp update_email_log_status(email_log, status, sent_at, error_message \\ nil) do
    email_log
    |> EmailLog.changeset(%{
      status: status,
      sent_at: sent_at,
      error_message: error_message
    })
    |> Repo.update()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [el], el.status == ^status)

  defp maybe_filter_campaign(query, nil), do: query

  defp maybe_filter_campaign(query, campaign_id),
    do: where(query, [el], el.campaign_id == ^campaign_id)

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, search) do
    escaped = Helpers.escape_like(String.downcase(search))
    term = "%#{escaped}%"

    where(
      query,
      [el],
      ilike(el.to_email, ^term) or
        ilike(el.subject, ^term)
    )
  end

  defp apply_email_template_sort(query, field, order) do
    direction = if order == "desc", do: :desc, else: :asc

    case field do
      "name" -> order_by(query, [et], [{^direction, et.name}])
      "subject" -> order_by(query, [et], [{^direction, et.subject}])
      "updated_at" -> order_by(query, [et], [{^direction, et.updated_at}])
      "inserted_at" -> order_by(query, [et], [{^direction, et.inserted_at}])
      # default
      _ -> order_by(query, [et], [{^direction, et.inserted_at}])
    end
  end

  defp apply_email_log_sort(query, field, order) do
    direction = if order == "desc", do: :desc, else: :asc

    case field do
      "sent_at" -> order_by(query, [el], [{^direction, el.sent_at}])
      "inserted_at" -> order_by(query, [el], [{^direction, el.inserted_at}])
      "to_email" -> order_by(query, [el], [{^direction, el.to_email}])
      "subject" -> order_by(query, [el], [{^direction, el.subject}])
      "status" -> order_by(query, [el], [{^direction, el.status}])
      # default
      _ -> order_by(query, [el], [{^direction, el.inserted_at}])
    end
  end
end
