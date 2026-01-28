defmodule MicelioWeb.Browser.DocsController do
  use MicelioWeb, :controller

  alias Micelio.Docs
  alias MicelioWeb.PageMeta

  def category(conn, %{"category" => category}) do
    category_info = Docs.get_category(category)

    if category_info do
      pages = Docs.pages_by_category(category)

      conn
      |> PageMeta.put(
        title_parts: [category_info.title, gettext("docs")],
        description: category_info.description,
        canonical_url: url(~p"/docs/#{category}")
      )
      |> render(:category,
        category: category,
        category_info: category_info,
        pages: pages
      )
    else
      conn
      |> put_status(:not_found)
      |> put_view(MicelioWeb.ErrorHTML)
      |> render(:"404")
    end
  end

  def show(conn, %{"category" => category, "id" => id}) do
    category_info = Docs.get_category(category)

    if category_info do
      page = Docs.get_page!(category, id)
      pages = Docs.pages_by_category(category)

      conn
      |> PageMeta.put(
        title_parts: [page.title, category_info.title, gettext("docs")],
        description: page.description,
        canonical_url: url(~p"/docs/#{category}/#{id}")
      )
      |> render(:show,
        page: page,
        category: category,
        category_info: category_info,
        pages: pages
      )
    else
      conn
      |> put_status(:not_found)
      |> put_view(MicelioWeb.ErrorHTML)
      |> render(:"404")
    end
  rescue
    _ ->
      conn
      |> put_status(:not_found)
      |> put_view(MicelioWeb.ErrorHTML)
      |> render(:"404")
  end
end
