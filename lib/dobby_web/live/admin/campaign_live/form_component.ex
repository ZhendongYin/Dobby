defmodule DobbyWeb.Admin.CampaignLive.FormComponent do
  use DobbyWeb, :live_component

  require Logger

  alias Dobby.Campaigns
  alias Dobby.Emails
  import Phoenix.Component

  @impl true
  def render(assigns) do
    pending_template_id = Map.get(assigns, :pending_template_id)

    selected_template_id =
      cond do
        pending_template_id not in [nil, ""] -> pending_template_id
        assigns.campaign_email_template -> assigns.campaign_email_template.id
        true -> ""
      end

    template_options =
      [{"", "請選擇模板"}] ++ Enum.map(assigns.email_template_options, fn t -> {t.id, t.name} end)

    assigns =
      assigns
      |> assign(:selected_template_id, selected_template_id)
      |> assign(:template_options, template_options)
      |> assign(:template_select_disabled?, Enum.empty?(assigns.email_template_options))

    ~H"""
    <div>
      <.admin_form_shell
        back_href={@return_to}
        eyebrow="Campaign"
        title={@title}
        subtitle="設定活動資訊、背景圖與預設通知，確保參與者體驗一致。"
      >
        <:form>
        <.form
          for={@form}
          id="campaign-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
        >
            <.input field={@form[:name]} type="text" label="Name" required />
            <.input field={@form[:description]} type="textarea" label="Description" rows="4" />

            <div class="grid grid-cols-2 gap-4">
              <.input
                field={@form[:starts_at]}
                type="datetime-local"
                label="Start Date"
                value={format_datetime_for_input(@form[:starts_at].value)}
                required
              />
              <.input
                field={@form[:ends_at]}
                type="datetime-local"
                label="End Date"
                value={format_datetime_for_input(@form[:ends_at].value)}
                required
              />
            </div>

            <.input
              field={@form[:status]}
              type="select"
              label="Status"
              options={status_options()}
              required
            />

            <div class="space-y-3">
              <label class="block text-sm font-semibold text-base-content">Background Image</label>

              <div
                :if={!@background_upload}
                class="rounded-lg border border-amber-200 bg-amber-50 p-4"
              >
                <p class="text-sm text-amber-800">
                  上傳功能暫時不可用，請刷新頁面重試。
                </p>
              </div>

              <div :if={@background_upload} class="grid gap-4 lg:grid-cols-[minmax(0,1fr),300px]">
                <div
                  phx-drop-target={if @background_upload, do: @background_upload.ref}
                  class="relative flex min-h-[220px] flex-col items-center justify-center rounded-2xl border-2 border-dashed border-base-300 bg-base-200/60 p-6 text-center transition hover:border-primary/40 hover:bg-base-100"
                >
                  <div class="space-y-3 text-center text-base-content relative z-10 w-full">
                    <div
                      :if={
                        @background_upload &&
                          Enum.empty?(@background_upload.entries) &&
                          !present?(@latest_background_image_url)
                      }
                      class="space-y-2"
                    >
                      <p class="text-sm font-medium">拖曳圖片至此或點擊下方按鈕</p>
                      <p class="text-xs text-base-content/60">
                        建議 1920x1080，接受 JPG / PNG / GIF / WebP，最大 10MB
                      </p>
                      <label class="inline-flex cursor-pointer items-center gap-2 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-white shadow hover:bg-primary/90">
                        <.live_file_input upload={@background_upload} class="sr-only" /> 選擇檔案
                      </label>
                    </div>

                    <div
                      :if={
                        @background_upload &&
                          Enum.empty?(@background_upload.entries) &&
                          present?(@latest_background_image_url)
                      }
                      class="space-y-2"
                    >
                      <p class="text-sm font-semibold text-primary">圖片已上傳</p>
                      <div class="relative mx-auto h-36 w-full max-w-[300px] overflow-hidden rounded-2xl border border-base-300 bg-base-100">
                        <img
                          src={@latest_background_image_url}
                          alt="Uploaded background preview"
                          class="h-full w-full object-cover"
                        />
                        <div class="absolute right-2 top-2 flex flex-col gap-2 z-10">
                          <label class="inline-flex cursor-pointer items-center rounded-full bg-base-100/90 px-3 py-1 text-[11px] font-semibold text-base-content shadow hover:bg-base-100">
                            <.live_file_input upload={@background_upload} class="sr-only" /> 重新選擇
                          </label>
                      <button
                        type="button"
                        phx-click="clear-uploaded-background"
                        class={[
                              "inline-flex items-center rounded-full px-3 py-1 text-[11px] font-semibold shadow transition",
                              upload_in_progress?(@background_upload) &&
                                "bg-rose-100/50 text-rose-300 cursor-not-allowed",
                              !upload_in_progress?(@background_upload) &&
                                "bg-rose-100/90 text-rose-700 hover:bg-rose-100"
                            ]}
                            disabled={upload_in_progress?(@background_upload)}
                          >
                            移除
                          </button>
                        </div>
                        <p class="absolute bottom-2 left-1/2 -translate-x-1/2 rounded-full bg-black/60 px-3 py-0.5 text-[11px] text-white">
                          尚未儲存
                        </p>
                      </div>
                      <p class="text-xs text-base-content/60">儲存後即會套用，重新選擇可覆蓋</p>
                    </div>
                  </div>
                  <div
                    :for={
                      entry <-
                        if @background_upload && @background_upload.entries &&
                             length(@background_upload.entries) > 0,
                           do: @background_upload.entries,
                           else: []
                    }
                    id={"upload-entry-#{entry.ref}"}
                    class="w-full space-y-3"
                  >
                    <div class="relative overflow-hidden rounded-2xl border border-base-300 bg-base-100">
                      <div
                        class="h-48 w-full bg-base-200 flex items-center justify-center overflow-hidden rounded-2xl"
                      >
                        <.live_img_preview
                          entry={entry}
                          class="h-48 w-full object-cover"
                        />
                      </div>
                    <button
                      type="button"
                      phx-click="cancel-upload"
                      phx-value-ref={entry.ref}
                      class="absolute right-3 top-3 inline-flex items-center rounded-full bg-base-100/80 px-3 py-1 text-xs font-semibold text-base-content shadow hover:bg-base-100 z-10"
                    >
                        移除
                      </button>
                    </div>
                    <div class="space-y-1 text-left text-xs text-base-content/60">
                      <p class="font-medium text-base-content/80">
                        {entry.client_name} · {format_file_size(entry.client_size)}
                      </p>
                      <div class="h-1.5 rounded-full bg-base-200">
                        <span
                          id={"progress-#{entry.ref}"}
                          class="block h-full rounded-full bg-primary transition-all"
                          style={"width: #{entry.progress}%"}
                        />
                      </div>
                    </div>
                  </div>

                  <%!-- <.live_file_input> is rendered within the labels above --%>
                </div>

                <div class="space-y-3 text-base-content">
                  <div
                    :if={current_background_url(@form, @latest_background_image_url)}
                    class="overflow-hidden rounded-2xl border border-base-300 bg-base-100"
                  >
                    <img
                      src={current_background_url(@form, @latest_background_image_url)}
                      alt="Current background"
                      class="h-48 w-full object-cover"
                    />
                    <p class="px-3 py-2 text-xs text-base-content/60">目前背景圖</p>
                  </div>
                  <p class="text-xs text-base-content/60">
                    如果未選擇新圖片，會沿用目前圖片或下方自訂網址。
                  </p>
                </div>
              </div>

              <div class="space-y-1">
                <.input
                  field={@form[:background_image_url]}
                  type="text"
                  label="Image URL（選填）"
                  placeholder="https://example.com/image.jpg 或 /uploads/image.jpg"
                />
                <p class="text-xs text-base-content/60">
                  手動提供圖片網址時可用 CDN；若同時上傳圖片，以上傳結果為主。
                </p>
              </div>

              <div
                :for={err <- if @background_upload, do: upload_errors(@background_upload), else: []}
                class="text-sm text-rose-600"
              >
                {error_to_string(err)}
              </div>
            </div>

            <.input field={@form[:theme_color]} type="color" label="Theme Color" />
            <.input field={@form[:no_prize_message]} type="text" label="No Prize Message" />
            <.input field={@form[:rules_text]} type="textarea" label="Rules Text" rows="4" />

            <div class="rounded-2xl border border-base-300 bg-base-200/50 px-4 py-3 text-sm text-base-content/70 space-y-3">
              <div class="flex items-start justify-between gap-3">
                <div>
                  <p class="font-semibold text-base-content">郵件通知設定</p>
                  <p class="text-xs text-base-content/60">
                    當獎品未指定模板時，系統會使用此預設模板寄送通知信。
                  </p>
                </div>
                <span
                  :if={@campaign_email_template}
                  class="inline-flex items-center gap-1 rounded-full bg-indigo-50 px-3 py-1 text-xs font-semibold text-indigo-700"
                >
                  <.icon name="hero-envelope" class="h-3.5 w-3.5" /> {@campaign_email_template.name}
                </span>
              </div>

              <div class="space-y-2">
                <label class="text-xs font-semibold text-base-content/70">選擇預設模板</label>
                <.select
                  name="campaign[default_template_id]"
                  value={@selected_template_id}
                  options={@template_options}
                  class="w-full rounded-2xl"
                  disabled={@template_select_disabled?}
                />
                <p class="text-xs text-base-content/60">
                  如需編輯模板內容，請至模板庫修改後再回來選擇。
                </p>
              </div>

              <p :if={!@campaign.id} class="text-xs text-base-content/60">
                儲存活動後即可指定預設模板。
              </p>

              <p
                :if={@template_select_disabled?}
                class="text-xs text-amber-600 bg-amber-50/70 border border-amber-200 rounded-xl px-4 py-3"
              >
                尚未建立郵件模板，請先至模板庫新增內容後再選擇。
              </p>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <.input field={@form[:enable_protection]} type="checkbox" label="Enable Protection" />
              <.input field={@form[:protection_count]} type="number" label="Protection Count" />
            </div>

            <div class="flex gap-4 mt-6">
              <.button_with_loading
                type="submit"
                variant="primary"
                class="px-4 py-2"
              >
                {if @action == :new, do: "建立活動", else: "更新活動"}
              </.button_with_loading>
              <.link
                navigate={@return_to}
                class="px-4 py-2 text-sm font-medium text-base-content/70 bg-base-100 border border-base-300 rounded-md hover:bg-base-200/70 transition-colors"
              >
                Cancel
              </.link>
            </div>
          </.form>
        </:form>
      </.admin_form_shell>
    </div>
    """
  end

  @impl true
  def update(%{campaign: campaign} = assigns, socket) do
    changeset =
      if assigns[:form] do
        # Use form from send_update if provided
        assigns[:form].source
      else
        Campaigns.change_campaign(campaign)
      end

    email_template_result = Emails.list_global_templates(%{page: 1, page_size: 1000})
    email_template_options = Map.get(email_template_result, :items, [])

    campaign_email_template =
      if campaign.id do
        Emails.get_default_email_template(campaign.id)
      else
        nil
      end

    # Ensure background_upload is always present and valid
    # It MUST come from the parent LiveView as a prop, NEVER from component's socket
    # This is critical: Phoenix validates uploads in the context where they're accessed
    # If we access socket.assigns.uploads, Phoenix will check if uploads are allowed in component context
    background_upload = assigns[:background_upload] || socket.assigns[:background_upload]

    # 确保 entries 是列表，避免 nil
    background_upload =
      if background_upload do
        entries = background_upload.entries || []
        %{background_upload | entries: entries}
      else
        nil
      end

    # If still nil, log error but continue - this should never happen in normal flow
    # The parent should always provide it via the initial render or send_update
    require Logger

    if is_nil(background_upload) do
      Logger.error(
        "FormComponent.update: background_upload is nil! assigns[:background_upload] = #{inspect(assigns[:background_upload])}, socket.assigns[:background_upload] = #{inspect(socket.assigns[:background_upload])}"
      )

      Logger.error(
        "FormComponent.update: This will prevent file uploads from working. Parent must provide upload config."
      )
    else
      Logger.debug(
        "FormComponent.update: background_upload is present, ref = #{background_upload.ref}, entries count = #{length(background_upload.entries)}"
      )
    end

    # State persistence for latest_background_image_url:
    # Priority 1: New value from assigns (highest priority - explicit update)
    # Priority 2: Existing value in socket (preserve newly uploaded image)
    # Priority 3: Campaign's value (initial state)
    latest_url =
      cond do
        assigns[:latest_background_image_url] != nil ->
          assigns[:latest_background_image_url]

        socket.assigns[:latest_background_image_url] != nil ->
          socket.assigns[:latest_background_image_url]

        true ->
          campaign.background_image_url
      end

    socket =
      socket
      |> assign(:title, assigns[:title])
      |> assign(:action, assigns[:action])
      |> assign(:return_to, assigns[:return_to])
      |> assign(:campaign, campaign)
      |> assign(:form, assigns[:form] || to_form(changeset))
      |> assign(:current_admin, assigns[:current_admin] || socket.assigns[:current_admin])
      |> assign(:latest_background_image_url, latest_url)
      |> assign(:email_template_options, email_template_options)
      |> assign(:campaign_email_template, campaign_email_template)
      |> assign(
        :pending_template_id,
        assigns[:pending_template_id] || socket.assigns[:pending_template_id] || nil
      )

    # Even if background_upload is nil, assign it to socket
    # This allows the template to check and display error messages
    # If we don't assign it, the template's :if checks will fail silently
    socket = assign(socket, :background_upload, background_upload)

    {:ok, socket}
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp upload_in_progress?(nil), do: false

  defp upload_in_progress?(upload) do
    upload.entries && Enum.any?(upload.entries, &(not &1.done?))
  end

  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(:not_accepted), do: "File type not accepted"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"

  defp current_background_url(form, pending_url) do
    cond do
      is_binary(pending_url) && String.trim(pending_url) != "" ->
        pending_url

      true ->
        value = form[:background_image_url] && form[:background_image_url].value

        case value do
          binary when is_binary(binary) and binary != "" -> binary
          _ -> nil
        end
    end
  end

  defp status_options do
    [
      {"Draft", "draft"},
      {"Active", "active"},
      {"Ended", "ended"},
      {"Disabled", "disabled"}
    ]
  end

  defp format_datetime_for_input(nil), do: ""

  defp format_datetime_for_input(%DateTime{} = dt) do
    # Convert UTC DateTime to local datetime string for input
    # Format: "YYYY-MM-DDTHH:mm"
    Calendar.strftime(dt, "%Y-%m-%dT%H:%M")
  end

  defp format_datetime_for_input(_), do: ""
end
