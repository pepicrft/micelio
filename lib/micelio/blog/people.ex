defmodule Micelio.Blog.People do
  @moduledoc """
  Compile-time registry of allowed blog authors.
  """

  @ruby %{id: :ruby, name: "Ruby"}
  @pedro %{id: :pedro, name: "Pedro Piñera Buendía"}

  @people %{
    ruby: @ruby,
    pedro: @pedro
  }

  def all, do: Map.values(@people)

  def get!(id) when is_atom(id), do: Map.fetch!(@people, id)

  def name!(id) when is_atom(id) do
    id |> get!() |> Map.fetch!(:name)
  end
end
