defmodule Micelio.ProjectsWorkspaceTest do
  use Micelio.DataCase, async: true

  alias Micelio.Hif.Project
  alias Micelio.Projects
  alias Micelio.Storage

  setup do
    base_dir =
      Path.join(System.tmp_dir!(), "micelio-workspace-#{System.unique_integer([:positive])}")

    storage_dir = Path.join(base_dir, "storage")
    source_dir = Path.join(base_dir, "source")

    File.mkdir_p!(storage_dir)
    File.mkdir_p!(source_dir)

    previous = Application.get_env(:micelio, Micelio.Storage)
    Application.put_env(:micelio, Micelio.Storage, backend: :local, local_path: storage_dir)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:micelio, Micelio.Storage)
        _ -> Application.put_env(:micelio, Micelio.Storage, previous)
      end

      File.rm_rf!(base_dir)
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
