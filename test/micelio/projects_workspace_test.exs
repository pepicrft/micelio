defmodule Micelio.ProjectsWorkspaceTest do
  use Micelio.DataCase, async: true

  alias Micelio.Mic.Project
  alias Micelio.Projects
  alias Micelio.Storage
  alias Micelio.StorageHelper

  setup do
    # Use isolated storage via process dictionary (no global state!)
    {:ok, storage} = StorageHelper.create_isolated_storage()
    Process.put(:micelio_storage_config, storage.config)

    # Create source directory for test files
    source_dir = Path.join(storage.base_dir, "source")
    File.mkdir_p!(source_dir)

    on_exit(fn ->
      Process.delete(:micelio_storage_config)
      StorageHelper.cleanup(storage)
    end)

    {:ok, %{source_dir: source_dir}}
  end

  test "seeds the Micelio workspace from a local path", %{source_dir: source_dir} do
    File.write!(Path.join(source_dir, "README.md"), "Micelio workspace\n")
    File.mkdir_p!(Path.join(source_dir, "lib"))
    File.write!(Path.join([source_dir, "lib", "app.ex"]), "IO.puts(\"hi\")\n")

    assert {:ok, %{project: project, file_count: 2, tree_hash: tree_hash}} =
             Projects.seed_micelio_workspace(source_dir)

    assert project.handle == "micelio"

    assert {:ok, head} = Project.get_head(project.id)
    assert head.position == 1
    assert head.tree_hash == tree_hash

    assert {:ok, tree} = Project.get_tree(project.id, tree_hash)
    assert Map.has_key?(tree, "README.md")
    assert Map.has_key?(tree, "lib/app.ex")

    readme_hash = Map.fetch!(tree, "README.md")
    assert {:ok, "Micelio workspace\n"} = Storage.get(Project.blob_key(project.id, readme_hash))
  end

  test "returns already_seeded on subsequent seed attempts", %{source_dir: source_dir} do
    File.write!(Path.join(source_dir, "README.md"), "Micelio workspace\n")

    assert {:ok, %{project: project}} = Projects.seed_micelio_workspace(source_dir)

    assert {:ok, %{project: same_project, already_seeded: true}} =
             Projects.seed_micelio_workspace(source_dir)

    assert same_project.id == project.id
  end

  test "skips configured seed when no path is provided" do
    assert {:ok, :skipped} = Projects.seed_micelio_workspace_if_configured(path: nil)
  end

  test "seeds configured workspace for a provided project", %{source_dir: source_dir} do
    File.write!(Path.join(source_dir, "README.md"), "Micelio workspace\n")

    assert {:ok, %{project: project}} = Projects.ensure_micelio_workspace()

    assert {:ok, %{project: seeded_project, file_count: 1}} =
             Projects.seed_micelio_workspace_if_configured(path: source_dir, project: project)

    assert seeded_project.id == project.id
  end
end
