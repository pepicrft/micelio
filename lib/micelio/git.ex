defmodule Micelio.Git do
  @moduledoc """
  Git operations powered by libgit2 through Zig NIFs.

  Functions are organized by domain, matching the underlying Zig file structure:
  - `status/*` - working tree status
  - `repository_*` - repository init and metadata
  - `tree_*` - tree listing and blob reading
  """

  use Zig,
    otp_app: :micelio,
    zig_code_path: "zig/git/git.zig",
    c: [
      link_lib: {:system, "git2"}
    ]

  # Status operations
  @spec status(String.t()) ::
          {:ok, [{String.t(), String.t()}]}
          | {:error,
             :libgit2_init_failed | :path_too_long | :repository_not_found | :status_failed}
  def status(_path), do: :erlang.nif_error(:nif_not_loaded)

  # Repository operations
  @spec repository_init(String.t()) ::
          :ok | {:error, :libgit2_init_failed | :path_too_long | :repository_init_failed}
  def repository_init(_path), do: :erlang.nif_error(:nif_not_loaded)

  @spec repository_default_branch(String.t()) ::
          {:ok, String.t()}
          | {:error,
             :libgit2_init_failed
             | :path_too_long
             | :repository_not_found
             | :head_not_found
             | :branch_name_not_found}
  def repository_default_branch(_path), do: :erlang.nif_error(:nif_not_loaded)

  # Tree operations
  @spec tree_list(String.t(), String.t(), String.t()) ::
          {:ok, [{String.t(), String.t(), String.t()}]}
          | {:error,
             :libgit2_init_failed
             | :path_too_long
             | :repository_not_found
             | :ref_too_long
             | :ref_not_found
             | :commit_not_found
             | :tree_not_found
             | :path_not_found
             | :subtree_not_found}
  def tree_list(_repo_path, _ref, _tree_path), do: :erlang.nif_error(:nif_not_loaded)

  @spec tree_blob(String.t(), String.t(), String.t()) ::
          {:ok, binary()}
          | {:error,
             :libgit2_init_failed
             | :path_too_long
             | :repository_not_found
             | :ref_too_long
             | :ref_not_found
             | :commit_not_found
             | :tree_not_found
             | :file_not_found
             | :not_a_file
             | :blob_not_found
             | :blob_content_error}
  def tree_blob(_repo_path, _ref, _file_path), do: :erlang.nif_error(:nif_not_loaded)
end
