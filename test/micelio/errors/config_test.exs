defmodule Micelio.Errors.ConfigTest do
  use ExUnit.Case, async: true

  alias Micelio.Errors.Config

  test "external_sentry_enabled? defaults to false when unset" do
    Application.delete_env(:micelio, :errors)

    assert Config.external_sentry_enabled?() == false
  after
    Application.delete_env(:micelio, :errors)
  end

  test "external_sentry_enabled? reads the configured value" do
    Application.put_env(:micelio, :errors, external_sentry_enabled: true)

    assert Config.external_sentry_enabled?() == true
  after
    Application.delete_env(:micelio, :errors)
  end

  test "retention_days defaults to 90 when unset" do
    Application.delete_env(:micelio, :errors)

    assert Config.retention_days() == 90
  after
    Application.delete_env(:micelio, :errors)
  end

  test "resolved_retention_days defaults to 30 when unset" do
    Application.delete_env(:micelio, :errors)

    assert Config.resolved_retention_days() == 30
  after
    Application.delete_env(:micelio, :errors)
  end

  test "unresolved_retention_days defaults to 90 when unset" do
    Application.delete_env(:micelio, :errors)

    assert Config.unresolved_retention_days() == 90
  after
    Application.delete_env(:micelio, :errors)
  end

  test "retention_days reads configured value" do
    Application.put_env(:micelio, :errors, retention_days: 30)

    assert Config.retention_days() == 30
  after
    Application.delete_env(:micelio, :errors)
  end

  test "capture_enabled? defaults to true when unset" do
    Application.delete_env(:micelio, :errors)

    assert Config.capture_enabled?() == true
  after
    Application.delete_env(:micelio, :errors)
  end

  test "capture_enabled? reads configured value" do
    Application.put_env(:micelio, :errors, capture_enabled: false)

    assert Config.capture_enabled?() == false
  after
    Application.delete_env(:micelio, :errors)
  end

  test "dedupe_window_seconds defaults to 300 when unset" do
    Application.delete_env(:micelio, :errors)

    assert Config.dedupe_window_seconds() == 300
  after
    Application.delete_env(:micelio, :errors)
  end

  test "capture rate limit defaults are applied when unset" do
    Application.delete_env(:micelio, :errors)

    assert Config.capture_rate_limit_per_kind_per_minute() == 100
    assert Config.capture_rate_limit_total_per_minute() == 1000
  after
    Application.delete_env(:micelio, :errors)
  end

  test "sampling defaults are applied when unset" do
    Application.delete_env(:micelio, :errors)

    assert Config.sampling_after_occurrences() == 100
    assert Config.sampling_rate() == 0.1
  after
    Application.delete_env(:micelio, :errors)
  end

  test "dedupe_window_seconds reads configured value" do
    Application.put_env(:micelio, :errors, dedupe_window_seconds: 120)

    assert Config.dedupe_window_seconds() == 120
  after
    Application.delete_env(:micelio, :errors)
  end

  test "notification defaults are applied when unset" do
    Application.delete_env(:micelio, :errors)

    assert Config.notification_threshold_count() == 10
    assert Config.notification_threshold_window_seconds() == 300
    assert Config.notification_fingerprint_rate_limit_seconds() == 3600
    assert Config.notification_total_rate_limit_seconds() == 3600
    assert Config.notification_total_rate_limit_max() == 10
  after
    Application.delete_env(:micelio, :errors)
  end

  test "notification config reads configured values" do
    Application.put_env(:micelio, :errors,
      notification_threshold_count: 5,
      notification_threshold_window_seconds: 120,
      notification_fingerprint_rate_limit_seconds: 1800,
      notification_total_rate_limit_seconds: 600,
      notification_total_rate_limit_max: 2
    )

    assert Config.notification_threshold_count() == 5
    assert Config.notification_threshold_window_seconds() == 120
    assert Config.notification_fingerprint_rate_limit_seconds() == 1800
    assert Config.notification_total_rate_limit_seconds() == 600
    assert Config.notification_total_rate_limit_max() == 2
  after
    Application.delete_env(:micelio, :errors)
  end
end
