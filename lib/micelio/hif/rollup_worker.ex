defmodule Micelio.Hif.RollupWorker do
  @moduledoc """
  Asynchronous rollup builder for conflict filters.
  """

  alias Micelio.Hif.ConflictIndex

  require Logger

  @supervisor Micelio.Hif.RollupSupervisor

  def enqueue(project_id, position, change_filter) do
    case Process.whereis(@supervisor) do
      nil ->
        Logger.debug("hif.rollup inline position=#{position} project=#{project_id}")
        ConflictIndex.maybe_update_rollups(project_id, position, change_filter)

      _pid ->
        Task.Supervisor.start_child(@supervisor, fn ->
          Logger.debug("hif.rollup async position=#{position} project=#{project_id}")
          start = System.monotonic_time()
          result = ConflictIndex.maybe_update_rollups(project_id, position, change_filter)
          elapsed = System.monotonic_time() - start

          :telemetry.execute(
            [:micelio, :hif, :rollup_build],
            %{duration: elapsed, position: position},
            %{project_id: project_id}
          )

          result
        end)

        :ok
    end
  end
end
