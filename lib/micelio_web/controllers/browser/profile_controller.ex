defmodule MicelioWeb.Browser.ProfileController do
  use MicelioWeb, :controller

  alias Micelio.Sessions
  alias MicelioWeb.PageMeta

  def show(conn, _params) do
    user = conn.assigns.current_user
    activity_counts = Sessions.activity_counts_for_user(user)

    conn
    |> PageMeta.put(
      title_parts: ["@#{user.account.handle}"],
      description: "Account settings and personal preferences.",
      canonical_url: url(~p"/account")
    )
    |> render(:show, user: user, activity_counts: activity_counts)
  end
end
