defmodule Micelio.Errors.Config do
  @moduledoc false

  def external_sentry_enabled? do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:external_sentry_enabled, false)
  end

  def retention_days do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:retention_days, 90)
  end

  def resolved_retention_days do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:resolved_retention_days, 30)
  end

  def unresolved_retention_days do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:unresolved_retention_days, 90)
  end

  def retention_archive_enabled? do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:retention_archive_enabled, false)
  end

  def retention_archive_prefix do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:retention_archive_prefix, "errors/archives")
  end

  def retention_vacuum_enabled? do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:retention_vacuum_enabled, true)
  end

  def retention_table_warn_threshold do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:retention_table_warn_threshold, 100_000)
  end

  def retention_oban_enabled? do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:retention_oban_enabled, false)
  end

  def capture_enabled? do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:capture_enabled, true)
  end

  def dedupe_window_seconds do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:dedupe_window_seconds, 300)
  end

  def capture_rate_limit_per_kind_per_minute do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:capture_rate_limit_per_kind_per_minute, 100)
  end

  def capture_rate_limit_total_per_minute do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:capture_rate_limit_total_per_minute, 1000)
  end

  def sampling_after_occurrences do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:sampling_after_occurrences, 100)
  end

  def sampling_rate do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:sampling_rate, 0.1)
  end

  def notification_threshold_count do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:notification_threshold_count, 10)
  end

  def notification_threshold_window_seconds do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:notification_threshold_window_seconds, 300)
  end

  def notification_fingerprint_rate_limit_seconds do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:notification_fingerprint_rate_limit_seconds, 3600)
  end

  def notification_total_rate_limit_seconds do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:notification_total_rate_limit_seconds, 3600)
  end

  def notification_total_rate_limit_max do
    Application.get_env(:micelio, :errors, [])
    |> Keyword.get(:notification_total_rate_limit_max, 10)
  end
end
