defmodule Micelio.Mic.RollupWorker do
  @moduledoc """
  Asynchronous rollup builder for conflict filters.
  """

  alias Micelio.Mic.ConflictIndex

  require Logger

  @supervisor Micelio.Mic.RollupSupervisor

  def enqueue(project_id, position, change_filter) do
    case Process.whereis(@supervisor) do
      nil ->
        Logger.debug("mic.rollup inline position=#{position} project=#{project_id}")
        ConflictIndex.maybe_update_rollups(project_id, position, change_filter)

      _pid ->
        Task.Supervisor.start_child(@supervisor, fn ->
          Logger.debug("mic.rollup async position=#{position} project=#{project_id}")
          start = System.monotonic_time()
          result = ConflictIndex.maybe_update_rollups(project_id, position, change_filter)
          elapsed = System.monotonic_time() - start

          :telemetry.execute(
            [:micelio, :mic, :rollup_build],
            %{duration: elapsed, position: position},
            %{project_id: project_id}
          )

          result
        end)

        :ok
    end
  end
end
