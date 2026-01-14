defmodule MicelioWeb.Browser.BlogHTML do
  @moduledoc """
  This module contains pages rendered by BlogController.
  """

  use MicelioWeb, :html

  alias Micelio.Blog.Models
  alias Micelio.Blog.People

  embed_templates "blog_html/*"

  def format_date(%Date{} = date) do
    Calendar.strftime(date, "%B %d, %Y")
  end

  def author_name(author_id) when is_atom(author_id), do: People.name!(author_id)
  def author_name(author_name) when is_binary(author_name), do: author_name

  def model_name(model_id) when is_atom(model_id), do: Models.name!(model_id)
end
