defmodule Micelio.Mic.SeedTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Mic.{Project, Seed}
  alias Micelio.Projects
  alias Micelio.Storage

  setup do
    base_dir = Path.join(System.tmp_dir!(), "micelio-seed-#{System.unique_integer([:positive])}")
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
