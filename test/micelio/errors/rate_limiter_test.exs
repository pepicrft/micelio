defmodule Micelio.Errors.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Micelio.Errors.RateLimiter

  setup do
    Application.put_env(:micelio, :errors,
      capture_rate_limit_per_kind_per_minute: 2,
      capture_rate_limit_total_per_minute: 3
    )

    RateLimiter.reset!()

    on_exit(fn ->
      Application.delete_env(:micelio, :errors)
      RateLimiter.reset!()
    end)

    :ok
  end

  test "enforces per-kind limits" do
    assert RateLimiter.allow?(:exception)
    assert RateLimiter.allow?(:exception)
    refute RateLimiter.allow?(:exception)
  end

  test "enforces total limits across kinds" do
    assert RateLimiter.allow?(:exception)
    assert RateLimiter.allow?(:plug_error)
    assert RateLimiter.allow?(:exception)
    refute RateLimiter.allow?(:liveview_crash)
  end
end
