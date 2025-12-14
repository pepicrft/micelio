defmodule Micelio.Git do
  @moduledoc """
  Git operations powered by libgit2 through Zig NIFs.
  """

  use Zig,
    otp_app: :micelio,
    zig_code_path: "./zig/git/status.zig",
    c: [
      link_lib: {:system, "git2"}
    ]

  @doc """
  Returns the git status for the repository at the given path.

  Returns `{:ok, entries}` where entries is a list of tuples `{file_path, status}`.
  Status can be:
  - "new" - newly added to index
  - "modified" - modified in index or working tree
  - "deleted" - deleted from index or working tree
  - "renamed" - renamed in index or working tree
  - "typechange" - type changed
  - "untracked" - untracked file
  - "ignored" - ignored file
  - "conflicted" - conflicted file

  ## Examples

      iex> Micelio.Git.status("/path/to/repo")
      {:ok, [{"README.md", "modified"}, {"new_file.txt", "untracked"}]}

  """
  @spec status(String.t()) :: {:ok, [{String.t(), String.t()}]} | {:error, atom()}
  def status(_path), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Initializes a new Git repository at the given path.

  Returns `:ok` on success.

  ## Examples

      iex> Micelio.Git.init("/tmp/new_repo")
      :ok

  """
  @spec init(String.t()) :: :ok | {:error, atom()}
  def init(_path), do: :erlang.nif_error(:nif_not_loaded)
end
