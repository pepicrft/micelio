defmodule Micelio.Theme.Generator.LLM do
  @moduledoc """
  LLM-backed daily theme generator.
  """

  @behaviour Micelio.Theme.Generator

  @impl true
  def generate(%Date{} = date) do
    config = Application.get_env(:micelio, Micelio.Theme, [])
    generate(date, config)
  end

  def generate(%Date{} = date, config) when is_list(config) do
    with {:ok, endpoint} <- fetch_config(config, :llm_endpoint),
         {:ok, api_key} <- fetch_config(config, :llm_api_key),
         model = Keyword.get(config, :llm_model, "gpt-4.1-mini"),
         {:ok, response} <- request_theme(endpoint, api_key, model, date) do
      parse_response(response.body)
    end
  end

  defp request_theme(endpoint, api_key, model, date) do
    payload = %{
      model: model,
      messages: [
        %{role: "system", content: "You are a design assistant that creates color themes."},
        %{role: "user", content: prompt(date)}
      ],
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "daily_theme",
          strict: true,
          schema: %{
            type: "object",
            properties: %{
              name: %{type: "string"},
              description: %{type: "string"},
              light: %{
                type: "object",
                properties: color_schema(),
                required: required_color_keys(),
                additionalProperties: false
              },
              dark: %{
                type: "object",
                properties: color_schema(),
                required: required_color_keys(),
                additionalProperties: false
              }
            },
            required: ["name", "description", "light", "dark"],
            additionalProperties: false
          }
        }
      }
    }

    Req.post(
      endpoint,
      json: payload,
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
      ],
      receive_timeout: 30_000
    )
  end

  defp parse_response(body) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> parse_response(decoded)
      {:error, _} -> decode_json_from_text(body)
    end
  end

  defp parse_response(%{"theme" => payload}) when is_map(payload), do: {:ok, payload}
  defp parse_response(%{theme: payload}) when is_map(payload), do: {:ok, payload}

  defp parse_response(payload) when is_map(payload) do
    cond do
      Map.has_key?(payload, "name") and Map.has_key?(payload, "description") ->
        {:ok, payload}

      Map.has_key?(payload, "output") ->
        text =
          get_in(payload, ["output", Access.at(0), "content", Access.at(0), "text"])

        decode_json_from_text(text)

      Map.has_key?(payload, "choices") ->
        text = get_in(payload, ["choices", Access.at(0), "message", "content"])
        decode_json_from_text(text)

      true ->
        {:error, :unexpected_response}
    end
  end

  defp parse_response(_), do: {:error, :unexpected_response}

  defp decode_json_from_text(nil), do: {:error, :unexpected_response}

  defp decode_json_from_text(text) when is_binary(text) do
    case JSON.decode(text) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> extract_json_from_text(text)
    end
  end

  defp extract_json_from_text(text) do
    case Regex.run(~r/\{.*\}/s, text) do
      [json] ->
        case JSON.decode(json) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :unexpected_response}
    end
  end

  defp fetch_config(config, key) do
    case Keyword.get(config, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: {:error, {:missing_config, key}}, else: {:ok, trimmed}

      nil ->
        {:error, {:missing_config, key}}
    end
  end

  defp prompt(date) do
    """
    Create a daily design personality for #{Date.to_iso8601(date)}.

    CRITICAL REQUIREMENTS:
    1. WCAG AA contrast: text must have 4.5:1 contrast ratio against background
    2. Light mode: dark text on light background (text should be near-black like #1a1a1a)
    3. Dark mode: light text on dark background (text should be near-white like #f0f0f0)
    4. Link colors must be visually distinct and have good contrast
    5. Activity colors: gradient from gray (activity0) to vibrant green (activity4)

    Color roles:
    - text: main body text color (must contrast strongly with background)
    - background: page background color
    - primary: headings and emphasis (similar contrast to text)
    - secondary: subheadings and less prominent text
    - muted: placeholder text, disabled states
    - border: dividers and borders
    - link: hyperlink color (must be distinct and accessible)
    - activity0-4: contribution graph colors (gray to green gradient)

    Font choices (ONLY use system/web-safe fonts that browsers have built-in):
    - fontBody: body text font stack. Choose from these safe options:
      * "system-ui, -apple-system, BlinkMacSystemFont, sans-serif" (modern system)
      * "Georgia, Times New Roman, serif" (classic serif)
      * "Palatino Linotype, Book Antiqua, serif" (elegant serif)
      * "Arial, Helvetica, sans-serif" (clean sans-serif)
      * "Verdana, Geneva, sans-serif" (readable sans-serif)
      * "Trebuchet MS, sans-serif" (friendly sans-serif)
    - fontMono: monospace font stack. Use: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"

    Respond with JSON only. Name should be creative (2-3 words). Description one sentence, ASCII only. No emojis.
    """
  end

  defp color_schema do
    %{
      text: %{type: "string"},
      background: %{type: "string"},
      primary: %{type: "string"},
      secondary: %{type: "string"},
      muted: %{type: "string"},
      border: %{type: "string"},
      link: %{type: "string"},
      activity0: %{type: "string"},
      activity1: %{type: "string"},
      activity2: %{type: "string"},
      activity3: %{type: "string"},
      activity4: %{type: "string"},
      fontBody: %{type: "string"},
      fontMono: %{type: "string"}
    }
  end

  defp required_color_keys do
    [
      "text",
      "background",
      "primary",
      "secondary",
      "muted",
      "border",
      "link",
      "activity0",
      "activity1",
      "activity2",
      "activity3",
      "activity4",
      "fontBody",
      "fontMono"
    ]
  end
end
