defmodule Micelio.Theme.Generator.StaticTest do
  use ExUnit.Case, async: true

  alias Micelio.Theme.Generator.Static

  @expected_activity %{
    "activity0" => "oklch(0.96 0 0)",
    "activity1" => "oklch(0.93 0.01 140)",
    "activity2" => "oklch(0.86 0.06 140)",
    "activity3" => "oklch(0.78 0.12 140)",
    "activity4" => "oklch(0.7 0.18 140)"
  }

  test "static generator uses light gray to green activity gradient" do
    dates = [~D[2024-01-01], ~D[2024-01-02], ~D[2024-01-03]]

    Enum.each(dates, fn date ->
      {:ok, theme} = Static.generate(date)

      for palette <- [theme["light"], theme["dark"]] do
        for {key, value} <- @expected_activity do
          assert palette[key] == value
        end
      end
    end)
  end
end
