defmodule MicelioWeb.Browser.BlogHtml do
  @moduledoc """
  This module contains pages rendered by BlogController.
  """

  use MicelioWeb, :html

  embed_templates "blog_html/*"

  def format_date(%Date{} = date) do
    Calendar.strftime(date, "%B %d, %Y")
  end
end