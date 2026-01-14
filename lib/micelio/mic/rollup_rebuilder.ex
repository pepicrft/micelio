defmodule Micelio.Mic.RollupRebuilder do
  @moduledoc """
  Rebuilds rollup indexes over landing ranges.
  """

  alias Micelio.Mic.{Binary, ConflictIndex}
  alias Micelio.Storage

  require Logger

  def rebuild(project_id, from_position, to_position) when from_position <= to_position do
    Logger.debug(
      "mic.rollup_rebuild project=#{project_id} from=#{from_position} to=#{to_position}"
    )

    Enum.each([1, 2, 3], fn level ->
      starts =
        ConflictIndex.rollup_starts(ConflictIndex.rollup_size(level), from_position, to_position)

      Enum.each(starts, fn start_position ->
        _ = ConflictIndex.build_rollup(project_id, level, start_position)
      end)
    end)

    :ok
  end

  def rebuild(_project_id, from_position, to_position) when from_position > to_position, do: :ok

  def rebuild_from_head(project_id, from_position \\ 1) do
    case Storage.get(head_key(project_id)) do
      {:ok, content} ->
        with {:ok, head} <- Binary.decode_head(content) do
          rebuild(project_id, from_position, head.position)
        end

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def head_position(project_id) do
    case Storage.get(head_key(project_id)) do
      {:ok, content} ->
        case Binary.decode_head(content) do
          {:ok, head} -> {:ok, head.position}
          {:error, _} -> {:ok, 0}
        end

      {:error, :not_found} ->
        {:ok, 0}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp head_key(project_id), do: "projects/#{project_id}/head"
end
