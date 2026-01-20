defmodule Micelio.ValidationEnvironments.ChecksTest do
  use ExUnit.Case, async: true

  alias Micelio.ValidationEnvironments.Checks

  test "enforces minimum coverage delta thresholds" do
    checks = Checks.default_checks()

    assert {:ok, results} =
             Checks.run(checks, Micelio.TestValidationExecutor, :instance_ref,
               min_coverage_delta: 0.02
             )

    assert results.coverage_delta == 0.03

    assert {:error, results} =
             Checks.run(checks, Micelio.TestValidationExecutor, :instance_ref,
               min_coverage_delta: 0.05
             )

    assert results.coverage_delta == 0.03
  end
end
