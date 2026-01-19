defmodule MicelioWeb.Browser.LegalController do
  use MicelioWeb, :controller

  alias MicelioWeb.PageMeta

  def legal(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Legal"],
      description: "Plain-language legal overview and responsibility notice for Micelio.",
      canonical_url: url(~p"/legal")
    )
    |> render(:legal)
  end

  def privacy(conn, _params), do: redirect(conn, to: ~p"/legal")

  def terms(conn, _params), do: redirect(conn, to: ~p"/legal")

  def cookies(conn, _params), do: redirect(conn, to: ~p"/legal")

  def impressum(conn, _params), do: redirect(conn, to: ~p"/legal")
end
