defmodule MicelioWeb.Browser.LegalController do
  use MicelioWeb, :controller

  alias MicelioWeb.PageMeta

  def privacy(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Privacy Policy"],
      description: "How Micelio processes personal data under GDPR (EU) and German law.",
      canonical_url: url(~p"/privacy")
    )
    |> render(:privacy)
  end

  def terms(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Terms of Service"],
      description: "Terms governing use of the Micelio service.",
      canonical_url: url(~p"/terms")
    )
    |> render(:terms)
  end

  def cookies(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Cookie Policy"],
      description: "Information about cookies and similar technologies used by Micelio.",
      canonical_url: url(~p"/cookies")
    )
    |> render(:cookies)
  end

  def impressum(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Impressum"],
      description: "Provider identification for Micelio (Germany).",
      canonical_url: url(~p"/impressum")
    )
    |> render(:impressum)
  end
end
