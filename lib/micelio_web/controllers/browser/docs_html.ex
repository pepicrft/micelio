defmodule MicelioWeb.Browser.DocsHTML do
  @moduledoc """
  This module contains pages rendered by DocsController.
  """

  use MicelioWeb, :html

  embed_templates "docs_html/*"

  def category_title(category_id, categories) do
    case Map.get(categories, category_id) do
      %{title: title} -> title
      _ -> category_id
    end
  end
end
