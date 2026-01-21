defmodule Micelio.Theme.Generator.StaticTest do
  use ExUnit.Case, async: true

  alias Micelio.Theme.Generator.Static

  @expected_light_activity %{
    "activity0" => "#ebedf0",
    "activity1" => "#c6e48b",
    "activity2" => "#7bc96f",
    "activity3" => "#239a3b",
    "activity4" => "#196127"
  }

  test "static generator uses consistent light activity gradient" do
    dates = [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]]

    Enum.each(dates, fn date ->
      {:ok, theme} = Static.generate(date)

      for {key, value} <- @expected_light_activity do
        assert theme["light"][key] == value,
               "Expected #{key} to be #{value} in light theme, got #{theme["light"][key]}"
      end
    end)
  end

  test "static generator returns proper theme structure" do
    {:ok, theme} = Static.generate(~D[2024-01-01])

    assert is_map(theme["light"])
    assert is_map(theme["dark"])
    assert is_binary(theme["name"])
    assert is_binary(theme["description"])
  end

  test "dark activity colors differ from light activity colors" do
    {:ok, theme} = Static.generate(~D[2024-01-01])

    assert theme["dark"]["activity0"] != theme["light"]["activity0"]
  end
end
