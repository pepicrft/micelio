defmodule Micelio.Theme.Storage.Local do
  @moduledoc """
  Local filesystem storage for daily theme payloads.
  """

  @behaviour Micelio.Theme.Storage

  @impl true
  def get(key) do
    Micelio.Storage.Local.get(key, base_path: base_path())
  end

  @impl true
  def put(key, content) do
    Micelio.Storage.Local.put(key, content, base_path: base_path())
  end

  defp base_path do
    config = Application.get_env(:micelio, Micelio.Theme, [])

    Keyword.get(
      config,
      :local_path,
      Path.join([System.tmp_dir!(), "micelio", "themes"])
    )
  end
end
