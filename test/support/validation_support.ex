defmodule Micelio.TestValidationProvider do
  @behaviour Micelio.AgentInfra.Provider

  @impl true
  def id, do: :test_provider

  @impl true
  def name, do: "Test Provider"

  @impl true
  def validate_request(request) do
    notify({:validate_request, request})
    :ok
  end

  @impl true
  def provision(request) do
    notify({:provision, request})
    {:ok, %{id: "test-vm"}}
  end

  @impl true
  def status(_ref), do: {:ok, %{state: :running, hostname: nil, ip_address: nil, metadata: %{}}}

  @impl true
  def terminate(ref) do
    notify({:terminate, ref})
    :ok
  end

  defp notify(message) do
    if pid = Process.get(:validation_test_pid) do
      send(pid, message)
    end

    :ok
  end
end

defmodule Micelio.TestValidationExecutor do
  @behaviour Micelio.ValidationEnvironments.Executor

  @impl true
  def run(_instance_ref, "mix", ["compile" | _], _env) do
    {:ok, %{exit_code: 0, stdout: "compiled", resource_usage: %{cpu_seconds: 1.0}}}
  end

  def run(_instance_ref, "mix", ["format" | _], _env) do
    {:ok, %{exit_code: 0, stdout: "formatted", resource_usage: %{cpu_seconds: 0.5}}}
  end

  def run(_instance_ref, "mix", ["test" | _], _env) do
    {:ok,
     %{
       exit_code: 0,
       stdout: "tests passed",
       resource_usage: %{cpu_seconds: 2.0, memory_mb: 128},
       coverage_delta: 0.03
     }}
  end

  def run(_instance_ref, _command, _args, _env) do
    {:ok, %{exit_code: 0, stdout: "ok", resource_usage: %{}}}
  end
end

defmodule Micelio.TestFailingValidationExecutor do
  @behaviour Micelio.ValidationEnvironments.Executor

  @impl true
  def run(_instance_ref, "mix", ["compile" | _], _env) do
    {:ok, %{exit_code: 0, stdout: "compiled", resource_usage: %{cpu_seconds: 1.0}}}
  end

  def run(_instance_ref, "mix", ["format" | _], _env) do
    {:ok, %{exit_code: 0, stdout: "formatted", resource_usage: %{cpu_seconds: 0.5}}}
  end

  def run(_instance_ref, "mix", ["test" | _], _env) do
    {:ok,
     %{
       exit_code: 1,
       stdout: "tests failed",
       resource_usage: %{cpu_seconds: 1.5, memory_mb: 128},
       coverage_delta: -0.02
     }}
  end

  def run(_instance_ref, _command, _args, _env) do
    {:ok, %{exit_code: 0, stdout: "ok", resource_usage: %{}}}
  end
end
