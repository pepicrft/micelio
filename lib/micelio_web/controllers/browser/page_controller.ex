defmodule MicelioWeb.Browser.PageController do
  use MicelioWeb, :controller

  alias Micelio.Projects
  alias MicelioWeb.PageMeta

  def home(conn, params) do
    popular_page = parse_popular_page(params)
    popular_limit = 6
    popular_offset = (popular_page - 1) * popular_limit

    popular_projects =
      Projects.list_popular_projects(limit: popular_limit + 1, offset: popular_offset)

    {popular_projects, popular_has_more} = split_popular_projects(popular_projects, popular_limit)

    conn
    |> PageMeta.put(
      title_parts: [],
      description: "Micelio is a forge designed for agent-first development.",
      canonical_url: url(~p"/")
    )
    |> assign(:popular_projects, popular_projects)
    |> assign(:popular_page, popular_page)
    |> assign(:popular_has_more, popular_has_more)
    |> render(:home)
  end

  defp parse_popular_page(params) do
    case Integer.parse(Map.get(params, "popular_page", "1")) do
      {page, _} when page > 0 -> page
      _ -> 1
    end
  end

  defp split_popular_projects(projects, limit) do
    if length(projects) > limit do
      {Enum.take(projects, limit), true}
    else
      {projects, false}
    end
  end
end
