defmodule Micelio.Theme.Storage do
  @moduledoc """
  Storage behavior for daily theme payloads.
  """

  @callback get(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback put(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
end
