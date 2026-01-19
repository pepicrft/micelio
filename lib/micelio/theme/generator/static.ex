defmodule Micelio.Theme.Generator.Static do
  @moduledoc """
  Deterministic daily theme generator for local development and tests.
  """

  @behaviour Micelio.Theme.Generator

  @palettes [
    %{
      name: "Ledger Ink",
      description: "Reserved, monochrome accents with a ledger-like calm.",
      light: %{
        "primary" => "#0f1419",
        "secondary" => "#3a4a55",
        "muted" => "#6b7b88",
        "border" => "#d6dde3",
        "activity0" => "#ebedf0",
        "activity1" => "#c6e48b",
        "activity2" => "#7bc96f",
        "activity3" => "#239a3b",
        "activity4" => "#196127"
      },
      dark: %{
        "primary" => "#f3f6f8",
        "secondary" => "#a8b6c1",
        "muted" => "#7e8d98",
        "border" => "#28313a",
        "activity0" => "#ebedf0",
        "activity1" => "#c6e48b",
        "activity2" => "#7bc96f",
        "activity3" => "#239a3b",
        "activity4" => "#196127"
      }
    },
    %{
      name: "Foundry Drift",
      description: "Warm metal accents with steady, industrial contrast.",
      light: %{
        "primary" => "#3b2f2a",
        "secondary" => "#6d4b3b",
        "muted" => "#8c6b5a",
        "border" => "#e1d5cc",
        "activity0" => "#ebedf0",
        "activity1" => "#c6e48b",
        "activity2" => "#7bc96f",
        "activity3" => "#239a3b",
        "activity4" => "#196127"
      },
      dark: %{
        "primary" => "#f4ede8",
        "secondary" => "#d1b6a4",
        "muted" => "#b19686",
        "border" => "#3a2f28",
        "activity0" => "#ebedf0",
        "activity1" => "#c6e48b",
        "activity2" => "#7bc96f",
        "activity3" => "#239a3b",
        "activity4" => "#196127"
      }
    },
    %{
      name: "Kelp Signal",
      description: "Deep sea accents with crisp, luminous highlights.",
      light: %{
        "primary" => "#0a3a3a",
        "secondary" => "#0f5c5c",
        "muted" => "#3a7a7a",
        "border" => "#d2e2e2",
        "activity0" => "#ebedf0",
        "activity1" => "#c6e48b",
        "activity2" => "#7bc96f",
        "activity3" => "#239a3b",
        "activity4" => "#196127"
      },
      dark: %{
        "primary" => "#e6f4f4",
        "secondary" => "#9fc9c9",
        "muted" => "#7da3a3",
        "border" => "#1f2f2f",
        "activity0" => "#ebedf0",
        "activity1" => "#c6e48b",
        "activity2" => "#7bc96f",
        "activity3" => "#239a3b",
        "activity4" => "#196127"
      }
    }
  ]

  @impl true
  def generate(%Date{} = date) do
    index = rem(Date.day_of_year(date) - 1, length(@palettes))
    palette = Enum.at(@palettes, index)

    {:ok,
     %{
       "name" => palette.name,
       "description" => palette.description,
       "light" => palette.light,
       "dark" => palette.dark
     }}
  end
end
