defmodule Micelio.Theme.Generator.StaticTest do
  use ExUnit.Case, async: true

  alias Micelio.Theme.Generator.Static

  @expected_activity %{
    "activity0" => "oklch(0.92 0 0)",
    "activity1" => "oklch(0.9 0.04 145)",
    "activity2" => "oklch(0.82 0.1 145)",
    "activity3" => "oklch(0.72 0.16 145)",
    "activity4" => "oklch(0.62 0.22 145)"
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
