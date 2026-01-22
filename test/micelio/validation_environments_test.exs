defmodule Micelio.ValidationEnvironmentsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.AITokens
  alias Micelio.PromptRequests
  alias Micelio.Projects
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

  defmodule FailingProvider do
    @behaviour Micelio.AgentInfra.Provider

    @impl true
    def id, do: :failing_provider

    @impl true
    def name, do: "Failing Provider"

    @impl true
    def validate_request(_request), do: :ok

    @impl true
    def provision(_request), do: {:error, :capacity}

    @impl true
    def status(_ref), do: {:ok, %{state: :running, hostname: nil, ip_address: nil, metadata: %{}}}

    @impl true
    def terminate(_ref), do: :ok
  end

  defp setup_prompt_request do
    {:ok, user} = Accounts.get_or_create_user_by_email("validation@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: "validation-org",
        name: "Validation Org"
      })

    {:ok, project} =
      Projects.create_project(%{
        handle: "validation-project",
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
          token_count: 1500,
          generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          system_prompt: "System",
          conversation: %{"messages" => [%{"role" => "user", "content" => "Do it"}]}
        },
        project: project,
        user: user
      )

    {:ok, _pool} = AITokens.create_token_pool(project, %{balance: 3000, reserved: 0})
    assert {:ok, _budget, _pool} = AITokens.upsert_task_budget(prompt_request, %{"amount" => "2000"})

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
    assert run.metrics["duration_ms"] > 0
    assert run.metrics["quality_score"] == 100
    assert run.metrics["quality_scores"]["build"] == 100
    assert run.metrics["quality_scores"]["test"] == 100
    assert run.resource_usage["cpu_seconds"] == 3.5
    assert run.resource_usage["memory_mb"] == 256
    assert length(run.check_results["checks"]) == 2
    assert Enum.at(run.check_results["checks"], 0)["stdout"] == "compiled"
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
    assert length(run.check_results["checks"]) == 2
    assert Enum.at(run.check_results["checks"], 0)["stdout"] == "format error"
    assert_received {:terminate, %{id: "vm-123"}}
  end

  test "fails validation when quality score is below minimum" do
    Process.put(:validation_test_pid, self())
    prompt_request = setup_prompt_request()

    checks = [
      %{id: "compile", label: "Compile", kind: :build, command: "compile", args: [], env: %{}},
      %{id: "test", label: "Test", kind: :test, command: "test", args: [], env: %{}}
    ]

    assert {:error, run} =
             ValidationEnvironments.run_for_prompt_request(prompt_request,
               provider_module: TestProvider,
               executor: TestExecutor,
               checks: checks,
               plan_attrs: plan_attrs(),
               min_quality_score: 101
             )

    assert run.status == :failed
    assert run.metrics["quality_score"] == 100
    assert run.metrics["quality_threshold_failed"] == true
    assert run.metrics["quality_threshold_min"] == 101
    assert_received {:terminate, %{id: "vm-123"}}
  end

  test "records failures that happen before checks run" do
    prompt_request = setup_prompt_request()

    checks = [
      %{id: "compile", label: "Compile", kind: :build, command: "compile", args: [], env: %{}}
    ]

    failing_plan_attrs =
      plan_attrs()
      |> Map.put(:provider, "failing_provider")

    assert {:error, run} =
             ValidationEnvironments.run_for_prompt_request(prompt_request,
               provider_module: FailingProvider,
               executor: TestExecutor,
               checks: checks,
               plan_attrs: failing_plan_attrs
             )

    assert run.status == :failed
    assert run.check_results["checks"] == []
    assert run.check_results["error"]["stage"] == "provision"
    assert run.check_results["error"]["reason"] =~ "capacity"
    assert run.metrics["failure_stage"] == "provision"
    assert run.completed_at
  end

  test "falls back to fly provider when primary is unavailable" do
    Process.put(:validation_test_pid, self())
    prompt_request = setup_prompt_request()

    checks = [
      %{id: "compile", label: "Compile", kind: :build, command: "compile", args: [], env: %{}},
      %{id: "test", label: "Test", kind: :test, command: "test", args: [], env: %{}}
    ]

    providers = %{"aws" => FailingProvider, "fly" => TestProvider}

    assert {:ok, run} =
             ValidationEnvironments.run_for_prompt_request(prompt_request,
               executor: TestExecutor,
               checks: checks,
               plan_attrs: plan_attrs(),
               providers: providers,
               fallback_provider_ids: ["fly"]
             )

    assert run.status == :passed
    assert run.provider == "fly"
    assert_received {:validate_request,
                     %Micelio.AgentInfra.ProvisioningRequest{provider: "fly"}}

    assert_received {:provision, %Micelio.AgentInfra.ProvisioningRequest{provider: "fly"}}
  end
end
