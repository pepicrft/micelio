defmodule MicelioWeb.Browser.ChangelogController do
  use MicelioWeb, :controller

  alias Micelio.Changelog

  def index(conn, _params) do
    entries = Changelog.all_entries()
    categories = Changelog.all_categories()
    versions = Changelog.all_versions()

    conn
    |> assign(:page_title, "Changelog")
    |> assign(:entries, entries)
    |> assign(:categories, categories)
    |> assign(:versions, versions)
    |> render(:index)
  end

  def show(conn, %{"id" => id}) do
    entry = Changelog.get_entry_by_id!(id)

    conn
    |> assign(:page_title, entry.title)
    |> assign(:entry, entry)
    |> render(:show)
  end

  def version(conn, %{"version" => version}) do
    entries = Changelog.get_entries_by_version!(version)

    conn
    |> assign(:page_title, "Changelog - Version #{version}")
    |> assign(:entries, entries)
    |> assign(:version, version)
    |> render(:version)
  end

  def category(conn, %{"category" => category}) do
    entries = Changelog.get_entries_by_category!(category)
    categories = Changelog.all_categories()

    conn
    |> assign(:page_title, "Changelog - #{String.capitalize(category)}")
    |> assign(:entries, entries)
    |> assign(:category, category)
    |> assign(:categories, categories)
    |> render(:category)
  end

  def rss(conn, _params) do
    entries = Changelog.recent_entries(20)

    conn
    |> put_resp_content_type("application/rss+xml")
    |> render(:rss, entries: entries, layout: false)
  end

  def atom(conn, _params) do
    entries = Changelog.recent_entries(20)

    conn
    |> put_resp_content_type("application/atom+xml")
    |> render(:atom, entries: entries, layout: false)
  end
end