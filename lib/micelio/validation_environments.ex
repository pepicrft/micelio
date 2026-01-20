defmodule Micelio.ValidationEnvironments do
  @moduledoc """
  Orchestrates ephemeral validation environments for contributions.
  """

  import Ecto.Query, warn: false

  alias Micelio.AgentInfra
  alias Micelio.PromptRequests.PromptRequest
  alias Micelio.Repo
  alias Micelio.ValidationEnvironments.{Checks, LocalExecutor, ValidationRun}

  @default_image "micelio/validation-runner:latest"

  def list_runs_for_prompt_request(%PromptRequest{} = prompt_request) do
    ValidationRun
    |> where([run], run.prompt_request_id == ^prompt_request.id)
    |> order_by([run], desc: run.inserted_at)
    |> Repo.all()
  end

  def create_run(%PromptRequest{} = prompt_request, attrs \\ %{}) do
    %ValidationRun{}
    |> ValidationRun.changeset(attrs)
    |> Ecto.Changeset.put_change(:prompt_request_id, prompt_request.id)
    |> Repo.insert()
  end

  def run_for_prompt_request(%PromptRequest{} = prompt_request, opts \\ []) do
    executor = Keyword.get(opts, :executor, LocalExecutor)
    checks = Keyword.get(opts, :checks, Checks.default_checks())
    plan_attrs = plan_attrs(Keyword.get(opts, :plan_attrs, %{}), opts)
    provider_id = Map.get(plan_attrs, :provider) || Map.get(plan_attrs, "provider")
    notify_pid = Keyword.get(opts, :notify_pid)

    result =
      with {:ok, run} <- create_run(prompt_request, %{status: :pending}),
           :ok <- notify(notify_pid, {:validation_started, run}),
           {:ok, request} <- AgentInfra.build_request(plan_attrs),
           {:ok, provider_module} <- resolve_provider(opts, provider_id),
           :ok <- validate_request(provider_module, request),
           {:ok, instance_ref} <- provider_module.provision(request),
           {:ok, run} <- mark_running(run, provider_id, instance_ref) do
        execute_checks(run, provider_module, instance_ref, executor, checks, opts)
      end

    notify(notify_pid, {:validation_finished, prompt_request.id, result})

    result
  end

  defp execute_checks(run, provider_module, instance_ref, executor, checks, opts) do
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)
    started_ms = System.monotonic_time(:millisecond)

    result =
      Checks.run(checks, executor, instance_ref, min_coverage_delta: opts[:min_coverage_delta])

    duration_ms = System.monotonic_time(:millisecond) - started_ms

    safe_terminate(provider_module, instance_ref)

    persist_results(run, started_at, duration_ms, result)
  end

  defp persist_results(run, started_at, duration_ms, {:ok, results}) do
    update_run(run, %{
      status: :passed,
      check_results: %{"checks" => results.checks},
      metrics: %{"duration_ms" => duration_ms},
      resource_usage: results.resource_usage,
      coverage_delta: results.coverage_delta,
      started_at: started_at,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp persist_results(run, started_at, duration_ms, {:error, results}) do
    update_run(run, %{
      status: :failed,
      check_results: %{"checks" => results.checks},
      metrics: %{"duration_ms" => duration_ms},
      resource_usage: results.resource_usage,
      coverage_delta: results.coverage_delta,
      started_at: started_at,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> case do
      {:ok, run} -> {:error, run}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp mark_running(run, provider_id, instance_ref) do
    update_run(run, %{
      status: :running,
      provider: to_string(provider_id),
      instance_ref: normalize_instance_ref(instance_ref),
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp update_run(run, attrs) do
    run
    |> ValidationRun.changeset(attrs)
    |> Repo.update()
  end

  defp resolve_provider(opts, provider_id) do
    case Keyword.get(opts, :provider_module) do
      nil -> AgentInfra.provider_module(provider_id)
      module -> {:ok, module}
    end
  end

  defp validate_request(provider_module, request) do
    if function_exported?(provider_module, :validate_request, 1) do
      provider_module.validate_request(request)
    else
      :ok
    end
  end

  defp normalize_instance_ref(ref) when is_map(ref), do: ref
  defp normalize_instance_ref(ref), do: %{"ref" => inspect(ref)}

  defp safe_terminate(provider_module, instance_ref) do
    provider_module.terminate(instance_ref)
  rescue
    _ -> :ok
  end

  defp notify(nil, _message), do: :ok

  defp notify(pid, message) when is_pid(pid) do
    send(pid, message)
    :ok
  end

  defp plan_attrs(attrs, opts) do
    provider_id =
      Map.get(attrs, :provider) ||
        Map.get(attrs, "provider") ||
        Keyword.get(opts, :provider_id, "aws")

    Map.merge(
      %{
        provider: provider_id,
        image: Keyword.get(opts, :image, @default_image),
        cpu_cores: Keyword.get(opts, :cpu_cores, 2),
        memory_mb: Keyword.get(opts, :memory_mb, 4096),
        disk_gb: Keyword.get(opts, :disk_gb, 20),
        ttl_seconds: Keyword.get(opts, :ttl_seconds, 1800),
        network: Keyword.get(opts, :network, "egress")
      },
      attrs
    )
  end
end
