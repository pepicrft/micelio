Mimic.copy(Micelio.Accounts)

# SQLite allows a single writer per database file. Keep max_cases at 1 by
# default and use MIX_TEST_PARTITION (mix test --partitions N) to parallelize
# across multiple database files.
max_cases =
  System.get_env("SQLITE_TEST_MAX_CASES")
  |> case do
    nil ->
      1

    value ->
      case Integer.parse(value) do
        {count, _} when count > 0 -> count
        _ -> 1
      end
  end

ExUnit.start(max_cases: max_cases)
Ecto.Adapters.SQL.Sandbox.mode(Micelio.Repo, :manual)
