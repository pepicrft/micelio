defmodule Micelio.Theme.Generator do
  @moduledoc """
  Behavior for daily theme generators.
  """

  @callback generate(Date.t()) :: {:ok, map()} | {:error, term()}
end
