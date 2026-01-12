defmodule Zig.Formatter do
  @behaviour Mix.Tasks.Format

  @impl Mix.Tasks.Format
  def features(_opts) do
    [extensions: [".zig"], local: true]
  end

  @impl Mix.Tasks.Format
  def format(contents, _opts) do
    contents
  end
end
