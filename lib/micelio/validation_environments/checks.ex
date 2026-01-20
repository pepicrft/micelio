defmodule Micelio.ValidationEnvironments.Checks do
  @moduledoc """
  Defines and runs validation checks for contributions.
  """

  @type check :: %{
          id: String.t(),
          label: String.t(),
          kind: atom(),
          command: String.t(),
          args: [String.t()],
          env: map()
        }

  def default_checks do
    [
      %{
        id: "compile",
        label: "Compile",
        kind: :build,
        command: "mix",
        args: ["compile", "--warnings-as-errors"],
        env: %{}
      },
      %{
        id: "format",
        label: "Format",
        kind: :style,
        command: "mix",
        args: ["format", "--check-formatted"],
        env: %{}
      },
      %{
        id: "test",
        label: "Test",
        kind: :test,
        command: "mix",
        args: ["test"],
        env: %{}
      }
    ]
  end

  def run(checks, executor, instance_ref, opts \\ []) do
    min_coverage_delta = Keyword.get(opts, :min_coverage_delta)

    Enum.reduce_while(checks, %{checks: [], coverage_delta: nil, resource_usage: %{}}, fn check,
                                                                                         acc ->
      started_at = System.monotonic_time(:millisecond)

      {:ok, result} = executor.run(instance_ref, check.command, check.args, check.env)

      duration_ms = System.monotonic_time(:millisecond) - started_at

      coverage_delta = Map.get(result, :coverage_delta) || acc.coverage_delta

      resource_usage =
        acc.resource_usage
        |> merge_resource_usage(Map.get(result, :resource_usage, %{}))

      entry = %{
        "id" => check.id,
        "label" => check.label,
        "kind" => Atom.to_string(check.kind),
        "command" => check.command,
        "args" => check.args,
        "env" => check.env,
        "exit_code" => result.exit_code,
        "stdout" => Map.get(result, :stdout, ""),
        "duration_ms" => duration_ms,
        "resource_usage" => Map.get(result, :resource_usage, %{})
      }

      updated_checks = acc.checks ++ [entry]

      if result.exit_code == 0 do
        {:cont, %{checks: updated_checks, coverage_delta: coverage_delta, resource_usage: resource_usage}}
      else
        {:halt, {:error, %{checks: updated_checks, coverage_delta: coverage_delta, resource_usage: resource_usage}}}
      end
    end)
    |> finalize_coverage(min_coverage_delta)
  end

  defp finalize_coverage({:error, results}, min_coverage_delta) do
    case coverage_threshold_failed?(results, min_coverage_delta) do
      true -> {:error, results}
      false -> {:error, results}
    end
  end

  defp finalize_coverage(results, min_coverage_delta) do
    case coverage_threshold_failed?(results, min_coverage_delta) do
      true -> {:error, results}
      false -> {:ok, results}
    end
  end

  defp coverage_threshold_failed?(_results, nil), do: false

  defp coverage_threshold_failed?(%{coverage_delta: nil}, _min), do: false

  defp coverage_threshold_failed?(%{coverage_delta: delta}, min) when is_number(min) do
    delta < min
  end

  defp merge_resource_usage(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_number(left_value) and is_number(right_value) do
        left_value + right_value
      else
        right_value
      end
    end)
  end
end
