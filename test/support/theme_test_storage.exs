require Jason

defmodule Micelio.Theme.TestStorage do
  @moduledoc false

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Agent.start_link(fn -> %{data: %{}, puts: 0, gets: 0} end, name: name)
  end

  def get(key, config) do
    name = Keyword.fetch!(config, :storage_state)

    Agent.get_and_update(name, fn state ->
      value = Map.get(state.data, key)
      next_state = %{state | gets: state.gets + 1}
      {value, next_state}
    end)
    |> case do
      nil -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  def put(key, content, config) do
    name = Keyword.fetch!(config, :storage_state)

    Agent.update(name, fn state ->
      %{
        state
        | data: Map.put(state.data, key, content),
          puts: state.puts + 1
      }
    end)

    {:ok, key}
  end

  def state(config) do
    name = Keyword.fetch!(config, :storage_state)
    Agent.get(name, & &1)
  end
end
