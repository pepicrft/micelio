defmodule Micelio.Mic.LandingWorkflowTest do
  use Micelio.DataCase, async: false

  alias Micelio.Accounts
  alias Micelio.Mic.{Binary, ConflictIndex, Landing, Project}
  alias Micelio.Projects
  alias Micelio.Sessions
  alias Micelio.Sessions.ChangeStore
  alias Micelio.Storage

  setup do
    base_dir =
      Path.join(System.tmp_dir!(), "micelio-landing-#{System.unique_integer([:positive])}")

    storage_dir = Path.join(base_dir, "storage")
    File.mkdir_p!(storage_dir)

    previous = Application.get_env(:micelio, Micelio.Storage)
    Application.put_env(:micelio, Micelio.Storage, backend: :local, local_path: storage_dir)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:micelio, Micelio.Storage)
        _ -> Application.put_env(:micelio, Micelio.Storage, previous)
      end

      File.rm_rf!(base_dir)
    end)

    :ok
  end

  test "lands a session end-to-end and persists storage artifacts" do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.get_or_create_user_by_email("landing-e2e-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "landing-org-#{unique}",
        name: "Landing Org #{unique}"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "landing-project-#{unique}",
        name: "Landing Project #{unique}",
        organization_id: organization.id
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "landing-session-#{unique}",
        goal: "Land workflow test",
        project_id: project.id,
        user_id: user.id,
        conversation: [
          %{"role" => "user", "content" => "Ship it"},
          %{"role" => "assistant", "content" => "Landing now"}
        ],
        decisions: [
          %{"decision" => "merge", "reasoning" => "ready"}
        ]
      })

    files = [
      %{"path" => "README.md", "content" => "Hello land\n", "change_type" => "added"},
      %{"path" => "lib/app.ex", "content" => "IO.puts(\"hi\")\n", "change_type" => "added"},
      %{"path" => "docs/old.txt", "change_type" => "deleted"}
    ]

    {:ok, session_with_changes, _stats} = ChangeStore.store_session_changes(session, files)
    assert session_with_changes.metadata["change_filter"]

    assert {:ok, %{position: 1, landed_at: landed_at}} =
             Landing.land_session(session_with_changes)

    assert %DateTime{} = landed_at

    assert {:ok, head} = Project.get_head(project.id)
    assert head.position == 1

    assert {:ok, tree} = Project.get_tree(project.id, head.tree_hash)
    assert Map.has_key?(tree, "README.md")
    assert Map.has_key?(tree, "lib/app.ex")
    refute Map.has_key?(tree, "docs/old.txt")

    readme_hash = Project.blob_hash_for_path(tree, "README.md")
    assert {:ok, "Hello land\n"} = Project.get_blob(project.id, readme_hash)

    app_hash = Project.blob_hash_for_path(tree, "lib/app.ex")
    assert {:ok, "IO.puts(\"hi\")\n"} = Project.get_blob(project.id, app_hash)

    assert {:ok, landing_binary} = Storage.get(landing_key(project.id, 1))
    assert {:ok, landing} = Binary.decode_landing(landing_binary)
    assert landing.session_id == session.session_id
    assert landing.position == 1
    assert landing.tree_hash == head.tree_hash
    assert landing.change_filter != nil

    assert {:ok, summary_binary} =
             Storage.get(session_summary_key(project.id, session.session_id))

    assert {:ok, summary} = Binary.decode_session_summary(summary_binary)
    assert summary.session_id == session.session_id
    assert summary.project_id == project.id
    assert summary.user_id == user.id
    assert summary.status == "landed"
    assert summary.conversation_count == 2
    assert summary.decisions_count == 1

    assert {:ok, paths} = ConflictIndex.load_path_index(project.id, 1)
    assert Enum.sort(paths) == Enum.sort(["README.md", "lib/app.ex", "docs/old.txt"])

    assert :ok = wait_for_rollup_tasks()
  end

  defp landing_key(project_id, position) do
    "projects/#{project_id}/landing/#{pad_position(position)}.bin"
  end

  defp session_summary_key(project_id, session_id) do
    "projects/#{project_id}/sessions/#{session_id}.bin"
  end

  defp pad_position(position) do
    position
    |> Integer.to_string()
    |> String.pad_leading(12, "0")
  end

  defp wait_for_rollup_tasks(attempts \\ 50, delay_ms \\ 20) do
    case Process.whereis(Micelio.Mic.RollupSupervisor) do
      nil ->
        :ok

      supervisor ->
        wait_until(
          fn ->
            Supervisor.which_children(supervisor) == []
          end,
          attempts,
          delay_ms
        )
    end
  end

  defp wait_until(fun, attempts, delay_ms) when is_function(fun, 0) do
    Enum.reduce_while(1..attempts, {:error, :timeout}, fn _, _acc ->
      if fun.() do
        {:halt, :ok}
      else
        Process.sleep(delay_ms)
        {:cont, {:error, :timeout}}
      end
    end)
  end
end
