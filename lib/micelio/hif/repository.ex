defmodule Micelio.Hif.Repository do
  @moduledoc """
  Compatibility wrapper for repository storage helpers.
  """

  alias Micelio.Hif.Project

  defdelegate get_head(project_id), to: Project
  defdelegate get_tree(project_id, tree_hash), to: Project
  defdelegate get_blob(project_id, blob_hash), to: Project
  defdelegate blob_hash_for_path(tree, file_path), to: Project
  defdelegate directory_exists?(tree, dir_path), to: Project
  defdelegate list_entries(tree, dir_path), to: Project
  defdelegate head_key(project_id), to: Project
  defdelegate tree_key(project_id, tree_hash), to: Project
  defdelegate blob_key(project_id, blob_hash), to: Project
end
