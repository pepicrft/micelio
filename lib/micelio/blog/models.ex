defmodule Micelio.Blog.Models do
  @moduledoc """
  Compile-time registry of known LLM model names used for writing.
  """

  @vega %{id: :vega, name: "Vega"}
  @gpt_5_2_high %{id: :gpt_5_2_high, name: "GPT-5.2 (high)"}

  @models %{
    vega: @vega,
    gpt_5_2_high: @gpt_5_2_high
  }

  def all, do: Map.values(@models)

  def get!(id) when is_atom(id), do: Map.fetch!(@models, id)

  def name!(id) when is_atom(id) do
    id |> get!() |> Map.fetch!(:name)
  end
end
