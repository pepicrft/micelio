defmodule Micelio.Errors.PipelineTest do
  use Micelio.DataCase, async: false

  import Plug.Test

  alias Micelio.Accounts
  alias Micelio.Errors.AgentReporter
  alias Micelio.Errors.Error
  alias Micelio.Errors.ObanReporter
  alias Micelio.Errors.Telemetry
  alias Micelio.Projects
  alias Micelio.Sessions
  alias Micelio.Repo

  require Logger

  defmodule TestView do
  end

  defmodule ErrorPlug do
    use Plug.Builder

    plug MicelioWeb.ErrorCapturePlug
    plug :boom

    def boom(_conn, _opts), do: raise("plug boom")
  end

  setup do
    Application.put_env(:micelio, :errors, capture_enabled: true, dedupe_window_seconds: 0)
    Repo.delete_all(Error)

    on_exit(fn ->
      Application.delete_env(:micelio, :errors)
    end)

    :ok
  end

  test "error capture plug persists plug crashes" do
    conn = conn(:get, "/boom")

    assert_raise RuntimeError, "plug boom", fn ->
      ErrorPlug.call(conn, [])
    end

    error = wait_for_error_by(:plug_error, "plug boom")

    assert error.context["path"] == "/boom"
    assert error.context["method"] == "GET"
    assert error.metadata["plug_kind"] == "error"
  end

  test "logger backend captures error logs" do
    Logger.error("logger boom", request_id: "req-123")

    error = wait_for_error_by(:exception, "logger boom")

    assert error.severity == :error
    assert error.metadata["request_id"] == "req-123"
  end

  test "Oban reporter captures job exceptions" do
    {:ok, user} = Accounts.get_or_create_user_by_email("oban-job@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "oban-job-org",
        name: "Oban Job Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "oban-job-project",
        name: "Oban Job Project",
        organization_id: organization.id
      })

    ObanReporter.handle_event(
      [:oban, :job, :exception],
      %{},
      %{
        reason: %RuntimeError{message: "oban crash"},
        stacktrace: [],
        kind: :error,
        job: %{
          id: 123,
          queue: "default",
          worker: "TestWorker",
          attempt: 2,
          max_attempts: 5,
          args: %{
            project_id: project.id,
            user_id: user.id,
            correlation_id: "job-abc"
          }
        }
      },
      nil
    )

    error = wait_for_error_by(:oban_job, "oban crash")

    assert error.user_id == user.id
    assert error.project_id == project.id
    assert error.metadata["job_id"] == 123
    assert error.metadata["queue"] == "default"
    assert error.metadata["worker"] == "TestWorker"
    assert error.metadata["attempt"] == 2
    assert error.metadata["max_attempts"] == 5
    assert error.metadata["args"]["project_id"] == project.id
    assert error.metadata["correlation_id"] == "job-abc"
  end

  test "Oban reporter captures job discards" do
    {:ok, user} = Accounts.get_or_create_user_by_email("oban-discard@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "oban-discard-org",
        name: "Oban Discard Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "oban-discard-project",
        name: "Oban Discard Project",
        organization_id: organization.id
      })

    reason = "oban discard"

    ObanReporter.handle_event(
      [:oban, :job, :discard],
      %{},
      %{
        reason: reason,
        job: %{
          id: 456,
          queue: "critical",
          worker: "DiscardWorker",
          attempt: 3,
          max_attempts: 3,
          args: %{
            correlation_id: "discard-456",
            project_id: project.id,
            user_id: user.id
          }
        }
      },
      nil
    )

    error = wait_for_error_by(:oban_job, "Oban job discarded: \"#{reason}\"")

    assert error.user_id == user.id
    assert error.project_id == project.id
    assert error.metadata["job_id"] == 456
    assert error.metadata["queue"] == "critical"
    assert error.metadata["worker"] == "DiscardWorker"
    assert error.metadata["attempt"] == 3
    assert error.metadata["max_attempts"] == 3
    assert error.metadata["correlation_id"] == "discard-456"
  end

  test "live view telemetry captures crashes" do
    Telemetry.handle_live_view_exception(
      [:phoenix, :live_view, :handle_info, :exception],
      %{},
      %{
        reason: %RuntimeError{message: "lv boom"},
        stacktrace: [],
        kind: :error,
        view: TestView,
        live_action: :show,
        params: %{"id" => "123"}
      },
      nil
    )

    error = wait_for_error_by(:liveview_crash, "lv boom")

    assert error.metadata["view"] == to_string(TestView)
    assert error.metadata["live_action"] == "show"
    assert error.metadata["params"]["id"] == "123"
  end

  test "agent reporter captures agent crashes with session context" do
    {:ok, user} = Accounts.get_or_create_user_by_email("agent-crash@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "agent-crash-org",
        name: "Agent Crash Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "agent-crash-project",
        name: "Agent Crash Project",
        organization_id: organization.id
      })

    {:ok, session} =
      Sessions.create_session(%{
        session_id: "agent-crash-session",
        goal: "Debug agent crash",
        project_id: project.id,
        user_id: user.id,
        conversation: [%{"role" => "user", "content" => "Start work"}],
        decisions: [%{"decision" => "Fix issue", "reasoning" => "Error report"}]
      })

    AgentReporter.capture_crash("agent error",
      session: session,
      correlation_id: "agent-123",
      action_limit: 5,
      async: false
    )

    error = Repo.get_by(Error, kind: :agent_crash, message: "agent error")

    assert error.user_id == user.id
    assert error.project_id == project.id
    assert error.metadata["agent_id"] == user.id
    assert error.metadata["agent_session_id"] == session.id
    assert error.metadata["agent_session_ref"] == "agent-crash-session"
    assert error.metadata["correlation_id"] == "agent-123"
    assert length(error.metadata["last_actions"]) == 2
  end

  test "agent reporter captures crashes without a session" do
    {:ok, user} = Accounts.get_or_create_user_by_email("agent-no-session@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "agent-no-session-org",
        name: "Agent No Session Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "agent-no-session-project",
        name: "Agent No Session Project",
        organization_id: organization.id
      })

    AgentReporter.capture_crash("agent error without session",
      user_id: user.id,
      project_id: project.id,
      correlation_id: "agent-no-session",
      async: false
    )

    error = Repo.get_by(Error, kind: :agent_crash, message: "agent error without session")

    assert error.user_id == user.id
    assert error.project_id == project.id
    assert error.metadata["agent_id"] == user.id
    assert error.metadata["project_id"] == project.id
    assert error.metadata["correlation_id"] == "agent-no-session"
  end

  defp wait_for_error_by(kind, message, attempts \\ 20) do
    Enum.reduce_while(1..attempts, nil, fn _attempt, _acc ->
      case Repo.get_by(Error, kind: kind, message: message) do
        nil ->
          Process.sleep(25)
          {:cont, nil}

        error ->
          {:halt, error}
      end
    end) || flunk("expected error #{inspect(kind)} with message #{inspect(message)}")
  end
end
