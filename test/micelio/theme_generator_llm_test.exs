defmodule Micelio.ThemeGeneratorLLMTest do
  # async: false because global Mimic mocking requires exclusive ownership
  use ExUnit.Case, async: false
  use Mimic

  alias Micelio.Theme.Generator.LLM

  setup :verify_on_exit!
  setup :set_mimic_global

  test "posts to the LLM endpoint and returns the theme payload" do
    date = ~D[2025-02-01]

    payload = %{
      "name" => "Ledger Ink",
      "description" => "Reserved monochrome accents.",
      "light" => %{
        "primary" => "#0f1419",
        "secondary" => "#3a4a55",
        "muted" => "#6b7b88",
        "border" => "#d6dde3",
        "activity0" => "oklch(0.25 0.01 240)",
        "activity1" => "oklch(0.45 0.12 210)",
        "activity2" => "oklch(0.55 0.16 210)",
        "activity3" => "oklch(0.65 0.2 210)",
        "activity4" => "oklch(0.75 0.22 210)"
      },
      "dark" => %{
        "primary" => "#f3f6f8",
        "secondary" => "#a8b6c1",
        "muted" => "#7e8d98",
        "border" => "#28313a",
        "activity0" => "oklch(0.25 0.01 240)",
        "activity1" => "oklch(0.45 0.12 210)",
        "activity2" => "oklch(0.55 0.16 210)",
        "activity3" => "oklch(0.65 0.2 210)",
        "activity4" => "oklch(0.75 0.22 210)"
      }
    }

    config = [
      llm_endpoint: "https://example.com/v1/responses",
      llm_api_key: "secret-key",
      llm_model: "gpt-4.1-mini"
    ]

    expect(Req, :post, fn endpoint, opts ->
      assert endpoint == "https://example.com/v1/responses"
      assert opts[:json][:model] == "gpt-4.1-mini"
      messages = opts[:json][:messages]
      assert is_list(messages)
      user_message = Enum.find(messages, &(&1[:role] == "user"))
      assert String.contains?(user_message[:content], "2025-02-01")

      assert Enum.any?(opts[:headers], fn {key, value} ->
               key == "authorization" and value == "Bearer secret-key"
             end)

      {:ok, %{body: %{"theme" => payload}}}
    end)

    assert {:ok, ^payload} = LLM.generate(date, config)
  end

  test "parses theme payload from text-only responses" do
    date = ~D[2025-02-02]

    payload = %{
      "name" => "Kelp Signal",
      "description" => "Deep sea accents with crisp highlights.",
      "light" => %{
        "primary" => "#0a3a3a",
        "secondary" => "#0f5c5c",
        "muted" => "#3a7a7a",
        "border" => "#d2e2e2",
        "activity0" => "oklch(0.25 0.01 240)",
        "activity1" => "oklch(0.45 0.12 175)",
        "activity2" => "oklch(0.55 0.16 175)",
        "activity3" => "oklch(0.65 0.2 175)",
        "activity4" => "oklch(0.75 0.22 175)"
      },
      "dark" => %{
        "primary" => "#e6f4f4",
        "secondary" => "#9fc9c9",
        "muted" => "#7da3a3",
        "border" => "#1f2f2f",
        "activity0" => "oklch(0.25 0.01 240)",
        "activity1" => "oklch(0.45 0.12 175)",
        "activity2" => "oklch(0.55 0.16 175)",
        "activity3" => "oklch(0.65 0.2 175)",
        "activity4" => "oklch(0.75 0.22 175)"
      }
    }

    config = [
      llm_endpoint: "https://example.com/v1/responses",
      llm_api_key: "secret-key"
    ]

    response = %{
      "choices" => [
        %{
          "message" => %{
            "content" => JSON.encode!(payload)
          }
        }
      ]
    }

    expect(Req, :post, fn _endpoint, _opts ->
      {:ok, %{body: response}}
    end)

    assert {:ok, decoded} = LLM.generate(date, config)
    assert decoded["name"] == "Kelp Signal"
    assert decoded["light"]["primary"] == "#0a3a3a"
  end
end
