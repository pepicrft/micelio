defmodule Micelio.Projects.ImportTest do
  use Micelio.DataCase

  alias Micelio.Accounts
  alias Micelio.Mic.{Landing, Project, Seed}
  alias Micelio.Projects
  alias Micelio.Sessions
  alias Micelio.Storage

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email("importer@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "import-org",
        name: "Import Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "import-project",
        name: "Import Project",
        organization_id: organization.id
      })

    storage_path = Path.join([System.tmp_dir!(), "micelio", "import-tests", Ecto.UUID.generate()])
    Process.put(:micelio_storage_config, backend: :local, local_path: storage_path)

    on_exit(fn ->
      Process.delete(:micelio_storage_config)
      File.rm_rf(storage_path)
    end)

    %{user: user, project: project}
  end

  test "run_project_import/1 stores bundle and updates head", %{user: user, project: project} do
    repo_path = create_git_repo("import-repo")

    {:ok, import} =
      Projects.create_project_import(project, user, %{
        source_url: repo_path
      })

    assert {:ok, import} = Projects.run_project_import(import)
    assert import.status == "completed"

    import = Projects.get_project_import(import.id)
    bundle_key = import.metadata["bundle_key"]
    assert is_binary(bundle_key)
    assert Storage.exists?(bundle_key)
    assert import.metadata["validation"] == "ok"

    assert {:ok, head} = Project.get_head(project.id)
    assert head != nil
    assert {:ok, tree} = Project.get_tree(project.id, head.tree_hash)
    assert Map.has_key?(tree, "README.md")
  end

  test "rollback_project_import/1 restores previous head", %{user: user, project: project} do
    seed_dir = create_seed_dir("seeded")

    {:ok, %{tree_hash: seed_hash}} = Seed.store_tree_from_path(project.id, seed_dir)

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "seed-session",
        goal: "Seed repository",
        project_id: project.id,
        user_id: user.id
      })

    {:ok, landing} = Landing.land_session(session, tree_hash: seed_hash)

    {:ok, _} =
      Sessions.land_session(session, %{
        landed_at: landing.landed_at,
        metadata: Map.put(session.metadata, "landing_position", landing.position)
      })

    {:ok, head_before} = Project.get_head(project.id)

    repo_path = create_git_repo("rollback-repo")

    {:ok, import} =
      Projects.create_project_import(project, user, %{
        source_url: repo_path
      })

    assert {:ok, import} = Projects.run_project_import(import)

    assert {:ok, head_after} = Project.get_head(project.id)
    refute head_after.tree_hash == head_before.tree_hash

    assert {:ok, rolled_back} = Projects.rollback_project_import(import)
    assert rolled_back.status == "rolled_back"

    assert {:ok, head_restored} = Project.get_head(project.id)
    assert head_restored.tree_hash == head_before.tree_hash
  end

  defp create_git_repo(label) do
    unless System.find_executable("git") do
      raise "git is required for import tests"
    end

    base =
      Path.join([System.tmp_dir!(), "micelio", "import-repos", label, Ecto.UUID.generate()])

    File.mkdir_p!(base)
    run_git(["init", "-b", "main", base])
    File.write!(Path.join(base, "README.md"), "Hello from #{label}\n")
    run_git(["-C", base, "add", "."])
    run_git([
      "-C",
      base,
      "-c",
      "user.email=importer@example.com",
      "-c",
      "user.name=Importer",
      "commit",
      "-m",
      "Initial commit"
    ])

    base
  end

  defp create_seed_dir(label) do
    base =
      Path.join([System.tmp_dir!(), "micelio", "import-seed", label, Ecto.UUID.generate()])

    File.mkdir_p!(base)
    File.write!(Path.join(base, "seed.txt"), "seeded content\n")
    base
  end

  defp run_git(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _} -> raise "git command failed: #{output}"
    end
  end
end
