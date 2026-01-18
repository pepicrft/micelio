defmodule Micelio.Theme do
  @moduledoc """
  Daily theme generation and caching.

  Themes are generated once per day, persisted to storage, and cached in memory.
  """

  require Logger

  @type tokens :: %{optional(String.t()) => String.t()}
  @type theme :: %{
          date: Date.t(),
          name: String.t(),
          description: String.t(),
          tokens: %{
            light: tokens(),
            dark: tokens()
          }
        }

  @default_personality %{
    name: "Baseline Mono",
    description: "Minimal contrast with steady, utilitarian accents."
  }

  @token_map %{
    "primary" => "--theme-ui-colors-primary",
    "secondary" => "--theme-ui-colors-secondary",
    "muted" => "--theme-ui-colors-muted",
    "border" => "--theme-ui-colors-border",
    "activity0" => "--theme-ui-colors-activity-0",
    "activity1" => "--theme-ui-colors-activity-1",
    "activity2" => "--theme-ui-colors-activity-2",
    "activity3" => "--theme-ui-colors-activity-3",
    "activity4" => "--theme-ui-colors-activity-4"
  }

  @token_reverse for {key, value} <- @token_map, into: %{}, do: {value, key}

  def config(opts \\ []) do
    :micelio
    |> Application.get_env(__MODULE__, [])
    |> Keyword.merge(opts)
    |> Keyword.put_new(:storage, Micelio.Theme.Storage.S3)
    |> Keyword.put_new(:generator, Micelio.Theme.Generator.LLM)
    |> Keyword.put_new(:prefix, "themes/daily")
  end

  def daily_theme(opts \\ []) do
    server = Keyword.get(opts, :server, Micelio.Theme.Server)
    GenServer.call(server, :daily_theme)
  end

  def daily_personality(opts \\ []) do
    theme = daily_theme(opts)
    %{name: theme.name, description: theme.description}
  end

  def css(opts \\ []) when is_list(opts) do
    theme = daily_theme(opts)
    css(theme)
  end

  defp css(%{tokens: tokens}) do
    light = Map.get(tokens, :light, %{})
    dark = Map.get(tokens, :dark, %{})

    blocks = [
      css_block(":root", light),
      css_block(":root[data-theme=\"light\"]", light),
      css_media_block(dark),
      css_block(":root[data-theme=\"dark\"]", dark)
    ]

    css =
      blocks
      |> Enum.reject(&empty_block?/1)
      |> Enum.join("\n")

    if css != "", do: css
  end

  def fetch_or_generate(config, date) do
    storage = Keyword.fetch!(config, :storage)
    key = daily_key(config, date)

    case storage_get(storage, key, config) do
      {:ok, content} ->
        case decode_theme(date, content) do
          {:ok, theme} -> {:ok, theme}
          {:error, _} -> generate_and_store(config, date, key)
        end

      {:error, :not_found} ->
        generate_and_store(config, date, key)

      {:error, reason} ->
        Logger.warning("Daily theme read failed: #{inspect(reason)}")
        generate_and_store(config, date, key)
    end
  end

  defp generate_and_store(config, date, key) do
    generator = Keyword.fetch!(config, :generator)

    case generator_generate(generator, date, config) do
      {:ok, payload} ->
        case theme_from_payload(date, payload) do
          {:ok, theme} ->
            persist_theme(config, key, theme)
            {:ok, theme}

          {:error, reason} ->
            Logger.warning("Daily theme payload invalid: #{inspect(reason)}")
            {:ok, default_theme(date)}
        end

      {:error, reason} ->
        Logger.warning("Daily theme generation failed: #{inspect(reason)}")
        {:ok, default_theme(date)}
    end
  end

  defp decode_theme(date, content) when is_binary(content) do
    with {:ok, payload} <- JSON.decode(content),
         {:ok, theme} <- theme_from_payload(date, payload) do
      {:ok, theme}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp theme_from_payload(date, payload) when is_map(payload) do
    name =
      payload
      |> fetch_value(["name", :name], @default_personality.name)
      |> to_string()

    description =
      payload
      |> fetch_value(["description", :description], @default_personality.description)
      |> to_string()

    light =
      payload
      |> fetch_value(["light", :light], %{})
      |> normalize_tokens()

    dark =
      payload
      |> fetch_value(["dark", :dark], %{})
      |> normalize_tokens()

    {:ok,
     %{
       date: date,
       name: name,
       description: description,
       tokens: %{
         light: light,
         dark: dark
       }
     }}
  end

  defp theme_from_payload(_date, _payload), do: {:error, :invalid_payload}

  defp theme_to_payload(theme) do
    %{
      "name" => theme.name,
      "description" => theme.description,
      "light" => denormalize_tokens(theme.tokens.light),
      "dark" => denormalize_tokens(theme.tokens.dark)
    }
  end

  defp normalize_tokens(tokens) when is_map(tokens) do
    Enum.reduce(tokens, %{}, fn {key, value}, acc ->
      token_key = Map.get(@token_map, to_string(key))

      if token_key do
        value = value |> to_string() |> String.trim()
        if value == "", do: acc, else: Map.put(acc, token_key, value)
      else
        acc
      end
    end)
  end

  defp normalize_tokens(_tokens), do: %{}

  defp denormalize_tokens(tokens) when is_map(tokens) do
    Enum.reduce(tokens, %{}, fn {key, value}, acc ->
      token_key = Map.get(@token_reverse, key, key)
      Map.put(acc, token_key, value)
    end)
  end

  defp denormalize_tokens(_tokens), do: %{}

  defp persist_theme(config, key, theme) do
    storage = Keyword.fetch!(config, :storage)
    payload = theme_to_payload(theme)

    case Jason.encode(payload) do
      {:ok, json} ->
        case storage_put(storage, key, json, config) do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.warning("Daily theme persist failed: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("Daily theme encoding failed: #{inspect(reason)}")
    end
  end

  defp default_theme(date) do
    %{
      date: date,
      name: @default_personality.name,
      description: @default_personality.description,
      tokens: %{light: %{}, dark: %{}}
    }
  end

  defp daily_key(config, date) do
    prefix = Keyword.get(config, :prefix, "themes/daily")
    "#{prefix}/#{Date.to_iso8601(date)}.json"
  end

  defp storage_get(storage, key, config) do
    if function_exported?(storage, :get, 2) do
      storage.get(key, config)
    else
      storage.get(key)
    end
  end

  defp storage_put(storage, key, content, config) do
    if function_exported?(storage, :put, 3) do
      storage.put(key, content, config)
    else
      storage.put(key, content)
    end
  end

  defp generator_generate(generator, date, config) do
    if function_exported?(generator, :generate, 2) do
      generator.generate(date, config)
    else
      generator.generate(date)
    end
  end

  defp fetch_value(payload, keys, default) do
    Enum.find_value(keys, default, fn key ->
      case payload do
        %{^key => value} -> value
        %{} -> nil
      end
    end)
  end

  defp css_block(_selector, tokens) when map_size(tokens) == 0, do: nil

  defp css_block(selector, tokens) do
    body =
      tokens
      |> Enum.map_join("\n", fn {key, value} -> "  #{key}: #{value};" end)

    "#{selector} {\n#{body}\n}"
  end

  defp css_media_block(tokens) when map_size(tokens) == 0, do: nil

  defp css_media_block(tokens) do
    body =
      tokens
      |> Enum.map_join("\n", fn {key, value} -> "    #{key}: #{value};" end)

    "@media (prefers-color-scheme: dark) {\n  :root {\n#{body}\n  }\n}"
  end

  defp empty_block?(block), do: block in [nil, ""]
end
