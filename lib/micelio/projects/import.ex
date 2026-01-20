defmodule Micelio.Projects.Import do
  @moduledoc """
  Handles importing repositories from external git forges.
  """

  alias Micelio.Mic.{Landing, Project, Seed}
  alias Micelio.Projects.ProjectImport
  alias Micelio.Repo
  alias Micelio.Sessions
  alias Micelio.Storage

  require Logger

  @git_env [{"GIT_TERMINAL_PROMPT", "0"}]

  def start_async(%ProjectImport{} = import) do
    case Task.Supervisor.start_child(Micelio.Projects.ImportSupervisor, fn ->
           run(import)
         end) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def run(%ProjectImport{} = import) do
    import =
      ProjectImport
      |> Repo.get!(import.id)
      |> Repo.preload([:project, :user])

    with {:ok, import} <- mark_running(import),
         {:ok, import, temp_dir} <- capture_metadata(import),
         {:ok, repo_dir, import} <- clone_repo(import, temp_dir),
         {:ok, import} <- validate_repo(import, repo_dir),
         {:ok, import} <- store_bundle(import, temp_dir, repo_dir),
         {:ok, import} <- mark_issue_migration(import),
         {:ok, import} <- finalize_import(import, temp_dir, repo_dir) do
      {:ok, mark_completed(import)}
    else
      {:error, reason, import} ->
        {:ok, mark_failed(import, reason)}

      {:error, reason} ->
        Logger.error("Import failed: #{inspect(reason)}")
        {:error, reason}
    after
      cleanup_temp_dir(import)
    end
  end

  def rollback(%ProjectImport{} = import) do
    import =
      ProjectImport
      |> Repo.get!(import.id)
      |> Repo.preload(:project)
    metadata = import.metadata || %{}
    head_key = Project.head_key(import.project_id)

    case Map.get(metadata, "previous_head") do
      nil ->
        with {:ok, _} <- Storage.delete(head_key),
             {:ok, import} <- update_import(import, %{status: "rolled_back"}) do
          {:ok, import}
        end

      encoded_head when is_binary(encoded_head) ->
        head_binary = Base.decode64!(encoded_head)

        with {:ok, _} <- Storage.put(head_key, head_binary),
             {:ok, import} <- update_import(import, %{status: "rolled_back"}) do
          {:ok, import}
        end
    end
  end

  defp mark_running(import) do
    update_import(import, %{
      status: "running",
      stage: "metadata",
      started_at: now(),
      error_message: nil
    })
  end

  defp capture_metadata(import) do
    import = update_forge(import)

    with {:ok, previous_head} <- fetch_previous_head(import.project_id),
         {:ok, import} <-
           update_import(import, %{
             metadata: Map.merge(import.metadata || %{}, previous_head),
             source_forge: import.source_forge
           }) do
      {:ok, import, temp_dir(import)}
    else
      {:error, reason} -> {:error, reason, import}
    end
  end

  defp clone_repo(import, temp_dir) do
    _ = File.rm_rf(temp_dir)
    File.mkdir_p!(temp_dir)
    repo_dir = Path.join(temp_dir, "repo.git")

    with {:ok, import} <- update_import(import, %{stage: "git_data_clone"}),
         :ok <- ensure_git_available(),
         {:ok, _output} <- run_git(["clone", "--mirror", import.source_url, repo_dir]) do
      {:ok, repo_dir, import}
    else
      {:error, reason} ->
        {:error, {:git_clone_failed, reason}, import}
    end
  end

  defp store_bundle(import, temp_dir, repo_dir) do
    bundle_path = Path.join(temp_dir, "repo.bundle")
    bundle_key = bundle_key(import.project_id, import.id)

    with {:ok, _} <- run_git(["--git-dir", repo_dir, "bundle", "create", bundle_path, "--all"]),
         {:ok, bundle} <- File.read(bundle_path),
         {:ok, _} <- Storage.put(bundle_key, bundle),
         {:ok, import} <-
           update_import(import, %{
             metadata:
               Map.merge(import.metadata || %{}, %{
                 "bundle_key" => bundle_key,
                 "bundle_size" => byte_size(bundle)
               })
           }),
         {:ok, import} <- store_default_branch(import, repo_dir) do
      {:ok, import}
    else
      {:error, reason} ->
        {:error, {:bundle_failed, reason}, import}
    end
  end

  defp validate_repo(import, repo_dir) do
    with {:ok, import} <- update_import(import, %{stage: "validation"}),
         {:ok, _} <- run_git(["--git-dir", repo_dir, "fsck", "--full"]),
         {:ok, import} <-
           update_import(import, %{
             metadata: Map.put(import.metadata || %{}, "validation", "ok")
           }) do
      {:ok, import}
    else
      {:error, reason} ->
        {:error, {:validation_failed, reason}, import}
    end
  end

  defp store_default_branch(import, repo_dir) do
    case run_git(["--git-dir", repo_dir, "symbolic-ref", "--quiet", "HEAD"]) do
      {:ok, ref} ->
        update_import(import, %{
          metadata: Map.put(import.metadata || %{}, "default_branch", String.trim(ref))
        })

      {:error, _} ->
        {:ok, import}
    end
  end

  defp mark_issue_migration(import) do
    update_import(import, %{
      stage: "issue_migration",
      metadata: Map.put(import.metadata || %{}, "issue_migration", "skipped")
    })
  end

  defp finalize_import(import, temp_dir, repo_dir) do
    work_dir = Path.join(temp_dir, "worktree")

    with {:ok, import} <- update_import(import, %{stage: "finalization"}),
         :ok <- File.mkdir_p(work_dir),
         {:ok, _} <-
           run_git(["--git-dir", repo_dir, "--work-tree", work_dir, "checkout", "-f"]),
         {:ok, %{file_count: file_count, tree_hash: tree_hash}} <-
           Seed.store_tree_from_path(import.project_id, work_dir),
         {:ok, session} <- create_import_session(import),
         {:ok, landing} <- Landing.land_session(session, tree_hash: tree_hash),
         {:ok, _} <-
           Sessions.land_session(session, %{
             landed_at: landing.landed_at,
             metadata:
               session.metadata
               |> Map.put("landing_position", landing.position)
           }),
         {:ok, import} <-
           update_import(import, %{
             metadata:
               Map.merge(import.metadata || %{}, %{
                 "file_count" => file_count,
                 "tree_hash" => Base.encode64(tree_hash),
                 "landing_position" => landing.position
               })
           }) do
      {:ok, import}
    else
      {:error, reason} ->
        {:error, {:finalization_failed, reason}, import}
    end
  end

  defp create_import_session(import) do
    session_id = "import-#{import.id}"

    Sessions.create_session(%{
      session_id: session_id,
      goal: "Import repository",
      project_id: import.project_id,
      user_id: import.user_id,
      metadata: %{
        "import_id" => import.id,
        "source_url" => import.source_url
      }
    })
  end

  defp mark_completed(import) do
    {:ok, import} =
      update_import(import, %{
        status: "completed",
        completed_at: now()
      })

    import
  end

  defp mark_failed(import, reason) do
    {:ok, import} =
      update_import(import, %{
        status: "failed",
        error_message: format_error(reason),
        completed_at: now()
      })

    import
  end

  defp update_forge(import) do
    source_forge =
      case infer_forge(import.source_url) do
        nil -> import.source_forge
        forge -> forge
      end

    %{import | source_forge: source_forge}
  end

  defp infer_forge(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        cond do
          String.contains?(host, "github.com") -> "github"
          String.contains?(host, "gitlab.com") -> "gitlab"
          String.contains?(host, "gitea") -> "gitea"
          true -> "other"
        end

      %URI{scheme: nil} ->
        "local"

      _ ->
        nil
    end
  end

  defp infer_forge(_), do: nil

  defp fetch_previous_head(project_id) do
    head_key = Project.head_key(project_id)

    case Storage.get(head_key) do
      {:ok, head_binary} ->
        {:ok, %{"previous_head" => Base.encode64(head_binary)}}

      {:error, :not_found} ->
        {:ok, %{"previous_head" => nil}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_import(import, attrs) do
    import
    |> ProjectImport.changeset(attrs)
    |> Repo.update()
  end

  defp temp_dir(%ProjectImport{id: id}) do
    Path.join([temp_root(), id])
  end

  defp temp_root do
    config = Application.get_env(:micelio, Micelio.Projects.Import, [])
    Keyword.get(config, :tmp_root, Path.join([System.tmp_dir!(), "micelio", "imports"]))
  end

  defp bundle_key(project_id, import_id) do
    "projects/#{project_id}/imports/#{import_id}/repo.bundle"
  end

  defp ensure_git_available do
    if System.find_executable("git") do
      :ok
    else
      {:error, :git_not_installed}
    end
  end

  defp run_git(args) do
    case System.cmd("git", args, stderr_to_stdout: true, env: @git_env) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  defp cleanup_temp_dir(nil), do: :ok

  defp cleanup_temp_dir(%ProjectImport{} = import) do
    _ = File.rm_rf(temp_dir(import))
    :ok
  end

  defp format_error({:git_clone_failed, reason}), do: "Git clone failed: #{reason}"
  defp format_error({:bundle_failed, reason}), do: "Git bundle failed: #{reason}"
  defp format_error({:validation_failed, reason}), do: "Validation failed: #{reason}"
  defp format_error({:finalization_failed, reason}), do: "Finalization failed: #{inspect(reason)}"
  defp format_error(reason), do: inspect(reason)

  defp now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end
end
