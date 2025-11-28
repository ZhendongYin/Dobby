defmodule Dobby.PrizeLibrary do
  @moduledoc """
  Prize templates that can be reused across campaigns.
  """

  import Ecto.Query, warn: false
  alias Dobby.Repo
  alias Dobby.PrizeLibrary.PrizeTemplate
  alias Dobby.Campaigns
  alias Dobby.Context.Helpers

  def list_templates(filters \\ %{}) do
    page = Helpers.fetch_integer_opt(filters, :page) || 1
    page_size = Helpers.fetch_integer_opt(filters, :page_size) || 20
    offset = (page - 1) * page_size
    sort_by = Helpers.fetch_opt(filters, :sort_by) || "name"
    sort_order = Helpers.fetch_opt(filters, :sort_order) || "asc"

    query =
      PrizeTemplate
      |> template_filters(filters)
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

  def get_template!(id), do: Repo.get!(PrizeTemplate, id)

  def create_template(attrs \\ %{}) do
    %PrizeTemplate{}
    |> PrizeTemplate.changeset(attrs)
    |> Repo.insert()
  end

  def update_template(%PrizeTemplate{} = template, attrs) do
    result =
      template
      |> PrizeTemplate.changeset(attrs)
      |> Repo.update()

    # 如果更新成功，同步更新所有使用该模板的奖品
    case result do
      {:ok, updated_template} ->
        # 同步模板更新到所有相关奖品
        Campaigns.sync_template_to_prizes(updated_template.id, attrs)
        {:ok, updated_template}

      error ->
        error
    end
  end

  def delete_template(%PrizeTemplate{} = template) do
    Repo.delete(template)
  end

  def change_template(%PrizeTemplate{} = template, attrs \\ %{}) do
    PrizeTemplate.changeset(template, attrs)
  end

  defp template_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:search, term}, query when is_binary(term) and term != "" ->
        escaped = Helpers.escape_like(String.downcase(term))
        like = "%#{escaped}%"

        from t in query,
          where:
            ilike(t.name, ^like) or
              ilike(fragment("coalesce(?, '')", t.description), ^like)

      _, query ->
        query
    end)
  end

  defp apply_sort(query, field, order) do
    direction = if order == "desc", do: :desc, else: :asc

    case field do
      "name" -> order_by(query, [t], [{^direction, t.name}])
      "updated_at" -> order_by(query, [t], [{^direction, t.updated_at}])
      "prize_type" -> order_by(query, [t], [{^direction, t.prize_type}])
      # default
      _ -> order_by(query, [t], [{^direction, t.name}])
    end
  end
end
