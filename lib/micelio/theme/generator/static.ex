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
        "text" => "#1a1a1a",
        "background" => "#ffffff",
        "primary" => "#0f1419",
        "secondary" => "#3a4a55",
        "muted" => "#6b7b88",
        "border" => "#d6dde3",
        "link" => "#0066cc",
        "activity0" => "#ebedf0",
        "activity1" => "#c6e48b",
        "activity2" => "#7bc96f",
        "activity3" => "#239a3b",
        "activity4" => "#196127",
        "fontBody" => "system-ui, -apple-system, sans-serif",
        "fontMono" => "ui-monospace, monospace"
      },
      dark: %{
        "text" => "#f0f0f0",
        "background" => "#0d1117",
        "primary" => "#f3f6f8",
        "secondary" => "#a8b6c1",
        "muted" => "#7e8d98",
        "border" => "#28313a",
        "link" => "#58a6ff",
        "activity0" => "#161b22",
        "activity1" => "#0e4429",
        "activity2" => "#006d32",
        "activity3" => "#26a641",
        "activity4" => "#39d353",
        "fontBody" => "system-ui, -apple-system, sans-serif",
        "fontMono" => "ui-monospace, monospace"
      }
    },
    %{
      name: "Foundry Drift",
      description: "Warm metal accents with steady, industrial contrast.",
      light: %{
        "text" => "#1c1917",
        "background" => "#faf9f7",
        "primary" => "#3b2f2a",
        "secondary" => "#6d4b3b",
        "muted" => "#8c6b5a",
        "border" => "#e1d5cc",
        "link" => "#9a3412",
        "activity0" => "#ebedf0",
        "activity1" => "#c6e48b",
        "activity2" => "#7bc96f",
        "activity3" => "#239a3b",
        "activity4" => "#196127",
        "fontBody" => "Georgia, serif",
        "fontMono" => "ui-monospace, monospace"
      },
      dark: %{
        "text" => "#f5f0eb",
        "background" => "#1c1917",
        "primary" => "#f4ede8",
        "secondary" => "#d1b6a4",
        "muted" => "#b19686",
        "border" => "#3a2f28",
        "link" => "#fb923c",
        "activity0" => "#292524",
        "activity1" => "#365314",
        "activity2" => "#4d7c0f",
        "activity3" => "#65a30d",
        "activity4" => "#84cc16",
        "fontBody" => "Georgia, serif",
        "fontMono" => "ui-monospace, monospace"
      }
    },
    %{
      name: "Kelp Signal",
      description: "Deep sea accents with crisp, luminous highlights.",
      light: %{
        "text" => "#0f172a",
        "background" => "#f8fafc",
        "primary" => "#0a3a3a",
        "secondary" => "#0f5c5c",
        "muted" => "#64748b",
        "border" => "#d2e2e2",
        "link" => "#0891b2",
        "activity0" => "#ebedf0",
        "activity1" => "#c6e48b",
        "activity2" => "#7bc96f",
        "activity3" => "#239a3b",
        "activity4" => "#196127",
        "fontBody" => "Inter, system-ui, sans-serif",
        "fontMono" => "ui-monospace, monospace"
      },
      dark: %{
        "text" => "#e2e8f0",
        "background" => "#0f172a",
        "primary" => "#e6f4f4",
        "secondary" => "#9fc9c9",
        "muted" => "#94a3b8",
        "border" => "#1e3a5f",
        "link" => "#22d3ee",
        "activity0" => "#1e293b",
        "activity1" => "#134e4a",
        "activity2" => "#0f766e",
        "activity3" => "#14b8a6",
        "activity4" => "#2dd4bf",
        "fontBody" => "Inter, system-ui, sans-serif",
        "fontMono" => "ui-monospace, monospace"
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
