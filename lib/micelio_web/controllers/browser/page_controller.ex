defmodule MicelioWeb.Browser.PageController do
  use MicelioWeb, :controller

  alias MicelioWeb.PageMeta

  def home(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: [],
      description: "Micelio is a forge designed for agent-first development.",
      canonical_url: url(~p"/")
    )
    |> render(:home)
  end
end
