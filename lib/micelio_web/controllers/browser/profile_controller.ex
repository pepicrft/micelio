defmodule MicelioWeb.Browser.ProfileController do
  use MicelioWeb, :controller

  alias MicelioWeb.PageMeta

  def show(conn, _params) do
    user = conn.assigns.current_user

    conn
    |> PageMeta.put(
      title_parts: ["@#{user.account.handle}"],
      description: "Account settings and personal preferences.",
      canonical_url: url(~p"/account")
    )
    |> render(:show, user: user)
  end
end
