defmodule Micelio.Theme.TestGenerator do
  @moduledoc false
  use Agent

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    initial = Keyword.get(opts, :payload, default_payload())
    Agent.start_link(fn -> %{payload: initial, calls: 0} end, name: name)
  end

  def generate(_date, config) do
    name = Keyword.fetch!(config, :generator_state)

    Agent.get_and_update(name, fn state ->
      next_state = %{state | calls: state.calls + 1}
      {{:ok, state.payload}, next_state}
    end)
  end

  def state(config) do
    name = Keyword.fetch!(config, :generator_state)
    Agent.get(name, & &1)
  end

  defp default_payload do
    %{
      "name" => "Test Signal",
      "description" => "Purpose-built for deterministic theme testing.",
      "light" => %{
        "primary" => "#112233",
        "secondary" => "#334455",
        "muted" => "#556677",
        "border" => "#dde3e8",
        "activity0" => "oklch(0.25 0.01 240)",
        "activity1" => "oklch(0.45 0.12 160)",
        "activity2" => "oklch(0.55 0.16 160)",
        "activity3" => "oklch(0.65 0.2 160)",
        "activity4" => "oklch(0.75 0.22 160)"
      },
      "dark" => %{
        "primary" => "#e9eef3",
        "secondary" => "#b2c1cf",
        "muted" => "#7c8a96",
        "border" => "#24303a",
        "activity0" => "oklch(0.25 0.01 240)",
        "activity1" => "oklch(0.45 0.12 160)",
        "activity2" => "oklch(0.55 0.16 160)",
        "activity3" => "oklch(0.65 0.2 160)",
        "activity4" => "oklch(0.75 0.22 160)"
      }
    }
  end
end
