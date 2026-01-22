defmodule Micelio.Errors.RetentionSchedulerTest do
  use ExUnit.Case, async: true

  import Mimic

  alias Micelio.Errors.Retention
  alias Micelio.Errors.RetentionScheduler

  setup :verify_on_exit!

  setup do
    Mimic.copy(Retention)
    :ok
  end

  test "run_cleanup runs retention directly when Oban is disabled" do
    existing = Application.get_env(:micelio, :errors, [])

    Application.put_env(
      :micelio,
      :errors,
      Keyword.put(existing, :retention_oban_enabled, false)
    )

    on_exit(fn -> Application.put_env(:micelio, :errors, existing) end)

    expect(Retention, :run, fn -> {:ok, %{}} end)

    assert {:ok, %{}} = RetentionScheduler.run_cleanup()
  end

  test "run_cleanup runs retention directly when Oban is enabled but unavailable" do
    existing = Application.get_env(:micelio, :errors, [])

    Application.put_env(
      :micelio,
      :errors,
      Keyword.put(existing, :retention_oban_enabled, true)
    )

    on_exit(fn -> Application.put_env(:micelio, :errors, existing) end)

    expect(Retention, :run, fn -> {:ok, %{}} end)

    assert {:ok, %{}} = RetentionScheduler.run_cleanup()
  end
end
