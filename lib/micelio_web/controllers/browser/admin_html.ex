defmodule MicelioWeb.Browser.AdminHTML do
  @moduledoc """
  HTML templates for the admin dashboard.
  """

  use MicelioWeb, :html

  embed_templates "admin_html/*"

  def format_datetime(nil), do: "-"

  def format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end
end
