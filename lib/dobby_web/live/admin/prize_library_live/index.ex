defmodule DobbyWeb.Admin.PrizeLibraryLive.Index do
  use DobbyWeb, :live_view

  alias Dobby.PrizeLibrary
  alias Dobby.PrizeLibrary.PrizeTemplate
  alias DobbyWeb.LiveViewHelpers

  @impl true
  def mount(_params, _session, socket) do
    filters = %{search: ""}

    {:ok,
     socket
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> assign(:page_size, 20)
     |> assign(:sort_by, "name")
     |> assign(:sort_order, "asc")
     |> assign(:form, new_template_form())
     |> assign(:editing_template, nil)
     |> assign(:return_to, ~p"/admin/prize-library")
     |> assign_image_upload()
     |> load_templates()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "新增模板")
    |> assign(:editing_template, nil)
    |> assign(:form, new_template_form())
    |> assign_image_upload()
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    template = PrizeLibrary.get_template!(id)

    socket
    |> assign(:page_title, "編輯模板")
    |> assign(:editing_template, template)
    |> assign(:form, to_form(PrizeLibrary.change_template(template)))
    |> assign_image_upload()
  end

  defp apply_action(socket, :index, params) do
    page = LiveViewHelpers.parse_integer(params["page"], socket.assigns[:page] || 1)

    page_size =
      LiveViewHelpers.parse_integer(params["page_size"], socket.assigns[:page_size] || 20)

    sort_by = params["sort_by"] || socket.assigns[:sort_by] || "name"
    sort_order = params["sort_order"] || socket.assigns[:sort_order] || "asc"

    socket
    |> assign(:page_title, "Prize Library")
    |> assign(:editing_template, nil)
    |> assign(:form, new_template_form())
    |> assign(:page, page)
    |> assign(:page_size, page_size)
    |> assign(:sort_by, sort_by)
    |> assign(:sort_order, sort_order)
    |> assign_image_upload()
    |> load_templates()
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    filters = Map.put(socket.assigns.filters, :search, search)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:page, 1)
     |> load_templates()}
  end

  def handle_event("change_page_size", %{"page_size" => page_size}, socket) do
    page_size = LiveViewHelpers.parse_integer(page_size, 20)

    {:noreply,
     socket
     |> assign(:page_size, page_size)
     |> assign(:page, 1)
     |> load_templates()
     |> push_patch(to: build_pagination_path(socket, 1, page_size))}
  end

  def handle_event("go_to_page", %{"page" => page}, socket) do
    page = LiveViewHelpers.parse_integer(page, 1)

    {:noreply,
     socket
     |> assign(:page, page)
     |> load_templates()}
  end

  def handle_event("sort", %{"field" => field, "order" => order}, socket) do
    {:noreply,
     socket
     |> assign(:sort_by, field)
     |> assign(:sort_order, order)
     |> assign(:page, 1)
     |> load_templates()
     |> push_patch(to: build_pagination_path(socket, 1, socket.assigns.page_size, field, order))}
  end

  @impl true
  def handle_event("save-template", %{"prize_template" => params}, socket) do
    require Logger
    Logger.debug("save-template: params before image upload: #{inspect(params)}")

    params = handle_image_upload(socket, params)
    Logger.debug("save-template: params after image upload: #{inspect(params)}")

    {result, success_message} =
      case socket.assigns.live_action do
        :edit ->
          template = socket.assigns.editing_template
          result = PrizeLibrary.update_template(template, params)

          # PrizeLibrary.update_template 已经自动同步了所有相关奖品
          case result do
            {:ok, _updated_template} ->
              {result, "模板已更新，相關獎品已同步"}

            _ ->
              {result, "模板已更新"}
          end

        _ ->
          {PrizeLibrary.create_template(params), "模板已新增，可於活動內匯入使用"}
      end

    case result do
      {:ok, _template} ->
        socket =
          socket
          |> put_flash(:info, success_message)
          |> assign(:templates, PrizeLibrary.list_templates(socket.assigns.filters))
          |> assign(:form, new_template_form())
          |> assign(:editing_template, nil)
          |> assign_image_upload()

        socket =
          if socket.assigns.live_action in [:new, :edit] do
            push_navigate(socket, to: ~p"/admin/prize-library")
          else
            socket
          end

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        socket =
          socket
          |> assign(:form, to_form(changeset))
          |> assign(:editing_template, changeset.data)
          |> assign_image_upload()

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :prize_image, ref)}
  end

  @impl true
  def handle_event("validate", %{"prize_template" => params}, socket) do
    require Logger
    Logger.debug("validate event: params = #{inspect(params)}")
    Logger.debug("validate event: uploads = #{inspect(socket.assigns.uploads)}")

    changeset =
      case socket.assigns.live_action do
        :edit ->
          template = socket.assigns.editing_template
          PrizeLibrary.change_template(template, params)

        _ ->
          PrizeLibrary.change_template(%PrizeTemplate{}, params)
      end
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  @impl true
  def handle_event("delete-template", %{"id" => id}, socket) do
    template = PrizeLibrary.get_template!(id)

    case PrizeLibrary.delete_template(template) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "模板已刪除")
          |> load_templates()

        socket =
          if (socket.assigns.live_action == :edit and socket.assigns.editing_template) &&
               socket.assigns.editing_template.id == template.id do
            push_patch(socket, to: socket.assigns.return_to)
          else
            socket
          end

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "刪除失敗，請稍後再試")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{scope: :admin, current_nav: :prize_library}}>
      <.page_container>
        <%= if assigns.live_action in [:new, :edit] do %>
          <.admin_form_shell
            back_href={~p"/admin/prize-library"}
            eyebrow="Prize Template"
            title={if @live_action == :edit, do: "編輯獎品模板", else: "新增獎品模板"}
            subtitle={
              if @live_action == :edit,
                do: "更新後將影響所有未來匯入該模板的活動。",
                else: "建立一次即可跨活動重複使用，後續匯入時再設定數量與概率。"
            }
          >
            <:form>
              <.form for={@form} phx-submit="save-template" phx-change="validate" class="space-y-6">
                <div class="grid gap-4 md:grid-cols-2">
                  <.input field={@form[:name]} type="text" label="名稱" required />
                  <.input
                    field={@form[:prize_type]}
                    type="select"
                    label="類型"
                    options={[{"實體", "physical"}, {"虛擬", "virtual"}, {"未中獎", "no_prize"}]}
                  />
                </div>

                <div class="space-y-4">
                  <label class="block text-sm font-semibold text-base-content">獎品圖片</label>
                  <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr),200px]">
                    <div
                      phx-drop-target={@uploads.prize_image.ref}
                      class="relative flex min-h-[200px] flex-col items-center justify-center rounded-xl border-2 border-dashed border-base-300 bg-base-200/40 p-6 text-center transition-all hover:border-primary/60 hover:bg-base-200/60"
                    >
                      <div :if={Enum.empty?(@uploads.prize_image.entries)} class="space-y-3">
                        <div class="mx-auto w-12 h-12 rounded-full bg-primary/15 flex items-center justify-center">
                          <.icon name="hero-photo" class="w-6 h-6 text-primary" />
                        </div>
                        <div class="space-y-1">
                          <p class="text-sm font-medium text-base-content/80">拖曳圖片至此或點擊下方按鈕</p>
                          <p class="text-xs text-base-content/60">
                            建議 800x800，接受 JPG / PNG / GIF / WebP，最大 5MB
                          </p>
                        </div>
                        <label
                          for="prize-upload-input"
                          class="inline-flex cursor-pointer items-center gap-2 rounded-xl bg-primary px-4 py-2 text-sm font-semibold text-white shadow-md hover:bg-primary/90 transition-all active:scale-95"
                        >
                          <.icon name="hero-arrow-up-tray" class="w-4 h-4" /> 選擇檔案
                        </label>
                      </div>

                      <div :for={entry <- @uploads.prize_image.entries} class="w-full space-y-3">
                        <div class="relative overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm">
                          <.live_img_preview entry={entry} class="h-48 w-full object-cover" />
                          <button
                            type="button"
                            phx-click="cancel-upload"
                            phx-value-ref={entry.ref}
                            class="absolute right-3 top-3 inline-flex items-center gap-1 rounded-xl border border-base-300 bg-base-100/95 px-3 py-1.5 text-xs font-semibold text-base-content/80 shadow-md hover:bg-base-200/60 transition-all active:scale-95"
                          >
                            <.icon name="hero-x-mark" class="w-3.5 h-3.5" /> 移除
                          </button>
                        </div>
                        <div class="space-y-2 text-left">
                          <p class="text-xs font-medium text-base-content/80">
                            {entry.client_name}
                          </p>
                          <p class="text-xs text-base-content/60">
                            {format_file_size(entry.client_size)}
                          </p>
                          <div class="h-2 rounded-full bg-base-300 overflow-hidden">
                            <span
                              class="block h-full rounded-full bg-primary transition-all duration-300"
                              style={"width: #{entry.progress}%"}
                            />
                          </div>
                        </div>
                      </div>

                      <.live_file_input
                        upload={@uploads.prize_image}
                        class="absolute inset-0 h-full w-full cursor-pointer opacity-0 focus-visible:outline-none"
                        id="prize-upload-input"
                      />
                    </div>

                    <div class="space-y-3">
                      <div
                        :if={current_image_url(@form)}
                        class="overflow-hidden rounded-xl border border-base-300 bg-base-100 shadow-sm"
                      >
                        <img
                          src={current_image_url(@form)}
                          alt="目前圖片"
                          class="h-48 w-full object-cover"
                        />
                        <p class="px-3 py-2 text-xs font-medium text-base-content/70 bg-base-200/60">
                          目前圖片
                        </p>
                      </div>
                      <p class="text-xs text-base-content/60 leading-relaxed">
                        如果未選擇新圖片，會沿用目前圖片或下方自訂網址。
                      </p>
                    </div>
                  </div>

                  <div class="space-y-2">
                    <.input
                      field={@form[:image_url]}
                      type="text"
                      label="圖片 URL（選填）"
                      placeholder="https://example.com/image.jpg 或 /uploads/image.jpg"
                    />
                    <p class="text-xs text-base-content/60 leading-relaxed">
                      手動提供圖片網址時可用 CDN；若同時上傳圖片，以上傳結果為主。
                    </p>
                  </div>

                  <div
                    :for={err <- upload_errors(@uploads.prize_image)}
                    class="rounded-lg bg-rose-50 border border-rose-200 px-3 py-2 text-sm text-rose-700"
                  >
                    <.icon name="hero-exclamation-circle" class="w-4 h-4 inline mr-1" />
                    {error_to_string(err)}
                  </div>
                </div>

                <div class="space-y-2">
                  <.input field={@form[:description]} type="textarea" label="描述" rows="4" />
                </div>

                <div class="space-y-2">
                  <.input
                    field={@form[:redemption_guide]}
                    type="textarea"
                    label="兌換說明 (可選)"
                    rows="4"
                  />
                </div>

                <div class="flex items-center justify-end gap-3 pt-4 border-t border-base-300">
                  <.secondary_button navigate={~p"/admin/prize-library"}>
                    取消
                  </.secondary_button>
                  <.primary_button type="submit" phx-disable-with="儲存中...">
                    {if @live_action == :edit, do: "更新模板", else: "儲存模板"}
                  </.primary_button>
                </div>
              </.form>
            </:form>
          </.admin_form_shell>
        <% else %>
          <!-- Index Page -->
          <div class="flex flex-wrap items-center justify-between gap-4 mb-8">
            <.page_header
              title="Prize Library"
              subtitle="建立一次即可跨活動重複使用的獎品模板，讓 Campaign 設定更快速、設計更一致。"
            />
            <.primary_button navigate={~p"/admin/prize-library/new"}>
              <.icon name="hero-plus-small" class="w-4 h-4" /> 新增模板
            </.primary_button>
          </div>

          <div class="mb-6">
            <.search_input
              name="search"
              value={@filters.search}
              placeholder="搜尋模板名稱或描述..."
              phx_change="search"
            />
          </div>

          <.card class="overflow-hidden">
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-base-300 bg-base-100 text-base-content">
                <thead class="bg-base-200/80">
                  <tr class="text-left text-xs font-semibold uppercase tracking-[0.2em] text-base-content/70">
                    <.sortable_header
                      field="name"
                      current_sort={@sort_by}
                      current_order={@sort_order}
                      label="模板"
                    />
                    <.sortable_header
                      field="prize_type"
                      current_sort={@sort_by}
                      current_order={@sort_order}
                      label="類型"
                    />
                    <.sortable_header
                      field="updated_at"
                      current_sort={@sort_by}
                      current_order={@sort_order}
                      label="最新更新"
                    />
                    <th class="px-4 py-3">備註</th>
                    <th class="px-4 py-3 text-right">管理</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-base-200 bg-base-100">
                  <tr
                    :for={template <- @templates}
                    id={"prize-template-#{template.id}"}
                    class="hover:bg-base-200/50 transition-colors text-sm"
                  >
                    <td class="px-4 py-4">
                      <p class="font-semibold text-base-content">{template.name}</p>
                      <p class="text-base-content/70 line-clamp-1">{template.description}</p>
                    </td>
                    <td class="px-4 py-4">
                      <.badge variant={type_badge_variant(template.prize_type)}>
                        {type_label(template.prize_type)}
                      </.badge>
                    </td>
                    <td class="px-4 py-4 text-base-content/70">
                      {Calendar.strftime(template.updated_at, "%Y-%m-%d %H:%M")}
                    </td>
                    <td class="px-4 py-4 text-xs text-base-content/70">
                      {template.redemption_guide || "—"}
                    </td>
                    <td class="px-4 py-4 text-right">
                      <div class="inline-flex items-center gap-3 text-sm">
                        <.link
                          patch={~p"/admin/prize-library/#{template.id}/edit"}
                          class="text-primary hover:text-primary/80"
                        >
                          編輯
                        </.link>
                        <button
                          type="button"
                          phx-click="delete-template"
                          phx-value-id={template.id}
                          data-confirm="確定要刪除此模板嗎？此動作無法復原。"
                          class="text-base-content/40 hover:text-error"
                        >
                          刪除
                        </button>
                      </div>
                    </td>
                  </tr>
                  <tr :if={Enum.empty?(@templates)}>
                    <td colspan="5" class="px-4 py-12 text-center text-base-content/50 text-sm">
                      尚未建立任何模板，點擊右上角的「新增模板」開始建立。
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </.card>

          <.pagination
            :if={!Enum.empty?(@templates)}
            page={@templates_page}
            page_size={@templates_page_size}
            total={@templates_total}
            path={~p"/admin/prize-library"}
            params={
              %{
                "search" => @filters.search,
                "sort_by" => @sort_by,
                "sort_order" => @sort_order
              }
            }
          />
        <% end %>
      </.page_container>
    </Layouts.app>
    """
  end

  defp new_template_form do
    %PrizeTemplate{}
    |> PrizeLibrary.change_template()
    |> to_form()
  end

  defp type_label("physical"), do: "實體"
  defp type_label("virtual"), do: "虛擬"
  defp type_label("no_prize"), do: "未中獎"
  defp type_label(_), do: "其他"

  defp type_badge_variant("physical"), do: "success"
  defp type_badge_variant("virtual"), do: "info"
  defp type_badge_variant("no_prize"), do: "default"
  defp type_badge_variant(_), do: "default"

  defp assign_image_upload(socket) do
    # Cancel any active upload entries before allowing a new upload
    socket =
      if socket.assigns[:uploads] && socket.assigns.uploads[:prize_image] do
        upload = socket.assigns.uploads[:prize_image]

        Enum.reduce(upload.entries, socket, fn entry, acc ->
          cancel_upload(acc, :prize_image, entry.ref)
        end)
      else
        socket
      end

    allow_upload(socket, :prize_image,
      accept: ~w(.jpg .jpeg .png .gif .webp),
      max_entries: 1,
      max_file_size: 5_000_000
    )
  end

  defp handle_image_upload(socket, params) do
    require Logger
    upload = socket.assigns.uploads[:prize_image]
    Logger.debug("handle_image_upload: upload = #{inspect(upload)}")

    if is_nil(upload) || Enum.empty?(upload.entries) do
      Logger.debug("handle_image_upload: no upload entries, returning params as-is")
      params
    else
      Logger.debug("handle_image_upload: processing #{length(upload.entries)} entries")

      uploaded_files =
        consume_uploaded_entries(socket, :prize_image, fn %{path: path}, entry ->
          Logger.debug("handle_image_upload: processing entry #{entry.client_name}")

          case Dobby.Uploads.ImageProcessor.process_image(path, width: 800, height: 800) do
            {:ok, processed_path} ->
              filename = generate_filename(entry.client_name)
              s3_path = "prize-library/#{filename}"

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

            {:error, _reason} ->
              filename = generate_filename(entry.client_name)
              s3_path = "prize-library/#{filename}"

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
          _ -> nil
        end)

      Logger.debug("handle_image_upload: result_url = #{inspect(result_url)}")

      case result_url do
        nil ->
          Logger.debug("handle_image_upload: no URL found, returning params as-is")
          params

        url ->
          Logger.debug("handle_image_upload: setting image_url to #{url}")
          Map.put(params, "image_url", url)
      end
    end
  end

  defp generate_filename(original_name) do
    ext = Path.extname(original_name)
    timestamp = System.system_time(:second)
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "#{timestamp}-#{random}#{ext}"
  end

  defp format_file_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_file_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_file_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp error_to_string(:too_large), do: "檔案過大（最大 5MB）"
  defp error_to_string(:too_many_files), do: "檔案數量過多"
  defp error_to_string(:not_accepted), do: "不支援的檔案類型"
  defp error_to_string(error), do: "上傳錯誤：#{inspect(error)}"

  defp current_image_url(form) do
    case Ecto.Changeset.get_field(form.source, :image_url) do
      nil -> nil
      "" -> nil
      url -> url
    end
  end

  defp load_templates(socket) do
    filters = %{
      search: socket.assigns.filters.search,
      page: socket.assigns.page,
      page_size: socket.assigns.page_size,
      sort_by: socket.assigns.sort_by,
      sort_order: socket.assigns.sort_order
    }

    result = PrizeLibrary.list_templates(filters)

    socket
    |> assign(:templates, result.items)
    |> assign(:templates_total, result.total)
    |> assign(:templates_page, result.page)
    |> assign(:templates_page_size, result.page_size)
  end

  defp build_pagination_path(socket, page, page_size, sort_by \\ nil, sort_order \\ nil) do
    params =
      %{
        "page" => Integer.to_string(page),
        "page_size" => Integer.to_string(page_size),
        "search" => socket.assigns.filters.search,
        "sort_by" => sort_by || socket.assigns.sort_by,
        "sort_order" => sort_order || socket.assigns.sort_order
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
      |> Map.new()

    ~p"/admin/prize-library?#{params}"
  end
end
