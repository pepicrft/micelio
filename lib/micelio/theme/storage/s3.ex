defmodule Micelio.Theme.Storage.S3 do
  @moduledoc """
  S3 storage for daily theme payloads.
  """

  @behaviour Micelio.Theme.Storage

  @impl true
  def get(key), do: Micelio.Storage.S3.get(key)

  @impl true
  def put(key, content), do: Micelio.Storage.S3.put(key, content)
end
