defmodule Micelio.Mic.SeedTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Mic.{Project, Seed}
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

  test "seeds project storage from a local path", %{source_dir: source_dir} do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "seed-org-#{unique}",
        name: "Seed Org #{unique}"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "seed-proj-#{unique}",
        name: "Seed Project #{unique}",
        organization_id: organization.id,
        visibility: "public"
      })

    File.write!(Path.join(source_dir, "README.md"), "Hello world\n")
    File.mkdir_p!(Path.join(source_dir, "lib"))
    File.write!(Path.join([source_dir, "lib", "app.ex"]), "IO.puts(\"hi\")\n")

    assert {:ok, %{file_count: 2, tree_hash: tree_hash}} =
             Seed.seed_project_from_path(project.id, source_dir)

    assert {:ok, head} = Project.get_head(project.id)
    assert head.position == 1
    assert head.tree_hash == tree_hash

    assert {:ok, tree} = Project.get_tree(project.id, tree_hash)
    assert Map.has_key?(tree, "README.md")
    assert Map.has_key?(tree, "lib/app.ex")

    readme_hash = Map.fetch!(tree, "README.md")
    assert {:ok, "Hello world\n"} = Storage.get(Project.blob_key(project.id, readme_hash))
  end

  test "returns already_seeded when head exists", %{source_dir: source_dir} do
    unique = System.unique_integer([:positive])

    {:ok, organization} =
      Accounts.create_organization(%{
        handle: "seed-org-repeat-#{unique}",
        name: "Seed Org Repeat #{unique}"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "seed-proj-repeat-#{unique}",
        name: "Seed Project Repeat #{unique}",
        organization_id: organization.id,
        visibility: "public"
      })

    File.write!(Path.join(source_dir, "README.md"), "Hello again\n")

    assert {:ok, _} = Seed.seed_project_from_path(project.id, source_dir)
    assert {:error, :already_seeded} = Seed.seed_project_from_path(project.id, source_dir)
  end
end
