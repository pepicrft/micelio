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
      input: prompt(date),
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "daily_theme",
          schema: %{
            type: "object",
            properties: %{
              name: %{type: "string"},
              description: %{type: "string"},
              light: %{
                type: "object",
                properties: color_schema(),
                required: required_color_keys()
              },
              dark: %{
                type: "object",
                properties: color_schema(),
                required: required_color_keys()
              }
            },
            required: ["name", "description", "light", "dark"]
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
    Respond only with JSON containing:
    - name: short theme name
    - description: one sentence, ASCII only
    - light: object with keys primary, secondary, muted, border, activity0..activity4
    - dark: object with keys primary, secondary, muted, border, activity0..activity4
    Activity colors must fade from light gray (activity0) to green (activity4).
    Colors must be valid CSS color values.
    No emojis. No extra text.
    """
  end

  defp color_schema do
    %{
      primary: %{type: "string"},
      secondary: %{type: "string"},
      muted: %{type: "string"},
      border: %{type: "string"},
      activity0: %{type: "string"},
      activity1: %{type: "string"},
      activity2: %{type: "string"},
      activity3: %{type: "string"},
      activity4: %{type: "string"}
    }
  end

  defp required_color_keys do
    [
      "primary",
      "secondary",
      "muted",
      "border",
      "activity0",
      "activity1",
      "activity2",
      "activity3",
      "activity4"
    ]
  end
end
