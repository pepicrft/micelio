defmodule Micelio.Theme.Generator.StaticTest do
  use ExUnit.Case, async: true

  alias Micelio.Theme.Generator.Static

  @expected_activity %{
    "activity0" => "#ebedf0",
    "activity1" => "#c6e48b",
    "activity2" => "#7bc96f",
    "activity3" => "#239a3b",
    "activity4" => "#196127"
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
