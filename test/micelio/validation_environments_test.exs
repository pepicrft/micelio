defmodule Micelio.ValidationEnvironmentsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Projects
  alias Micelio.PromptRequests
  alias Micelio.ValidationEnvironments

  defmodule TestProvider do
    @behaviour Micelio.AgentInfra.Provider

    @impl true
    def id, do: :test_provider

    @impl true
    def name, do: "Test Provider"

    @impl true
    def validate_request(request) do
      send(Process.get(:validation_test_pid), {:validate_request, request})
      :ok
    end

    @impl true
    def provision(request) do
      send(Process.get(:validation_test_pid), {:provision, request})
      {:ok, %{id: "vm-123"}}
    end

    @impl true
    def status(_ref), do: {:ok, %{state: :running, hostname: nil, ip_address: nil, metadata: %{}}}

    @impl true
    def terminate(ref) do
      send(Process.get(:validation_test_pid), {:terminate, ref})
      :ok
    end
  end

  defmodule TestExecutor do
    @behaviour Micelio.ValidationEnvironments.Executor

    @impl true
    def run(_instance_ref, "compile", _args, _env) do
      {:ok, %{exit_code: 0, stdout: "compiled", resource_usage: %{cpu_seconds: 1.1}}}
    end

    def run(_instance_ref, "test", _args, _env) do
      {:ok,
       %{
         exit_code: 0,
         stdout: "tests passed",
         resource_usage: %{cpu_seconds: 2.4, memory_mb: 256},
         coverage_delta: 0.02
       }}
    end

    def run(_instance_ref, "format", _args, _env) do
      {:ok, %{exit_code: 1, stdout: "format error", resource_usage: %{cpu_seconds: 0.4}}}
    end
  end

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  defp setup_prompt_request do
    handle = unique_handle("validation")
    {:ok, user} = Accounts.get_or_create_user_by_email("user-#{handle}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "org-#{handle}",
        name: "Validation Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "project-#{handle}",
        name: "Validation Project",
        organization_id: organization.id
      })

    {:ok, prompt_request} =
      PromptRequests.create_prompt_request(
        %{
          title: "Validate contribution",
          prompt: "Do the thing",
          result: "Output",
          model: "gpt-4.1",
          model_version: "2025-02-01",
          origin: :ai_generated,
          token_count: 820,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: project,
        user: user
      )

    prompt_request
  end

  defp plan_attrs do
    %{
      provider: "aws",
      image: "micelio/validation-runner:latest",
      cpu_cores: 2,
      memory_mb: 1024,
      disk_gb: 10,
      ttl_seconds: 1200,
      network: "egress"
    }
  end

  test "runs validation checks and records metrics" do
    Process.put(:validation_test_pid, self())
    prompt_request = setup_prompt_request()

    checks = [
      %{id: "compile", label: "Compile", kind: :build, command: "compile", args: [], env: %{}},
      %{id: "test", label: "Test", kind: :test, command: "test", args: [], env: %{}}
    ]

    assert {:ok, run} =
             ValidationEnvironments.run_for_prompt_request(prompt_request,
               provider_module: TestProvider,
               executor: TestExecutor,
               checks: checks,
               plan_attrs: plan_attrs()
             )

    assert run.status == :passed
    assert run.coverage_delta == 0.02
    assert run.metrics["duration_ms"] >= 0
    assert run.resource_usage["cpu_seconds"] == 3.5
    assert run.resource_usage["memory_mb"] == 256
    assert length(run.check_results["checks"]) == 2
    assert_received {:validate_request, _request}
    assert_received {:provision, _request}
    assert_received {:terminate, %{id: "vm-123"}}
  end

  test "fails validation when a check exits non-zero" do
    Process.put(:validation_test_pid, self())
    prompt_request = setup_prompt_request()

    checks = [
      %{id: "format", label: "Format", kind: :style, command: "format", args: [], env: %{}},
      %{id: "test", label: "Test", kind: :test, command: "test", args: [], env: %{}}
    ]

    assert {:error, run} =
             ValidationEnvironments.run_for_prompt_request(prompt_request,
               provider_module: TestProvider,
               executor: TestExecutor,
               checks: checks,
               plan_attrs: plan_attrs()
             )

    assert run.status == :failed
    assert length(run.check_results["checks"]) == 1
    assert_received {:terminate, %{id: "vm-123"}}
  end
end
