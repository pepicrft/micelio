defmodule Micelio.Blog.Post do
  @moduledoc """
  A blog post struct for NimblePublisher.
  """

  alias Micelio.Blog.Models
  alias Micelio.Blog.People

  @enforce_keys [:id, :author, :title, :body, :description, :tags, :date]
  defstruct [:id, :author, :model, :title, :body, :description, :tags, :date]

  def build(filename, attrs, body) do
    [year, month_day_id] = filename |> Path.rootname() |> Path.split() |> Enum.take(-2)
    [month, day, id] = String.split(month_day_id, "-", parts: 3)

    date = Date.from_iso8601!("#{year}-#{month}-#{day}")

    attrs = normalize_attrs!(attrs)

    struct!(
      __MODULE__,
      [
        id: id,
        date: date,
        body: body
      ] ++ Map.to_list(attrs)
    )
  end

  defp normalize_attrs!(%{author: author_id} = attrs) when is_atom(author_id) do
    _ = People.get!(author_id)

    case Map.fetch(attrs, :model) do
      :error -> attrs
      {:ok, nil} -> Map.delete(attrs, :model)
      {:ok, model_id} when is_atom(model_id) -> Map.put(attrs, :model, Models.get!(model_id).id)
      {:ok, model_name} when is_binary(model_name) -> invalid_model!(model_name)
    end
  end

  defp normalize_attrs!(%{author: author_name} = _attrs) when is_binary(author_name) do
    raise ArgumentError,
          "blog post author must be one of #{People.all() |> Enum.map(& &1.id) |> inspect()}, got: #{inspect(author_name)}"
  end

  defp invalid_model!(model_name) do
    raise ArgumentError,
          "blog post model must be one of #{Models.all() |> Enum.map(& &1.id) |> inspect()}, got: #{inspect(model_name)}"
  end
end
