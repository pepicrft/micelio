defmodule Micelio.Theme.Server do
  @moduledoc false

  use GenServer

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    config = Micelio.Theme.config(opts)
    {:ok, %{date: nil, theme: nil, config: config}}
  end

  @impl true
  def handle_call(:daily_theme, _from, state) do
    today = Date.utc_today()

    if state.date == today and state.theme do
      {:reply, state.theme, state}
    else
      {:ok, theme} = Micelio.Theme.fetch_or_generate(state.config, today)
      {:reply, theme, %{state | date: today, theme: theme}}
    end
  end
end
