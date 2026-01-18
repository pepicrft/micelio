defmodule Micelio.ThemeTest do
  use ExUnit.Case, async: true

  setup do
    unique = System.unique_integer([:positive])
    storage_state = {:global, {:theme_storage, unique}}
    generator_state = {:global, {:theme_generator, unique}}
    server_name = {:global, {:theme_server, unique}}
    prefix = "themes/test"

    start_supervised!({Micelio.Theme.TestStorage, name: storage_state})
    start_supervised!({Micelio.Theme.TestGenerator, name: generator_state})

    config = [
      storage: Micelio.Theme.TestStorage,
      generator: Micelio.Theme.TestGenerator,
      storage_state: storage_state,
      generator_state: generator_state,
      prefix: prefix
    ]

    start_supervised!({Micelio.Theme.Server, Keyword.put(config, :name, server_name)})

    {:ok, %{config: config, server: server_name, prefix: prefix}}
  end

  test "loads the daily theme from storage without calling the generator", %{
    config: config,
    server: server,
    prefix: prefix
  } do
    date = Date.utc_today()
    key = "#{prefix}/#{Date.to_iso8601(date)}.json"

    payload = %{
      "name" => "Stored Theme",
      "description" => "Loaded from storage.",
      "light" => %{"primary" => "#111111"},
      "dark" => %{"primary" => "#eeeeee"}
    }

    {:ok, _} = Micelio.Theme.TestStorage.put(key, Jason.encode!(payload), config)

    theme = Micelio.Theme.daily_theme(server: server)
    assert theme.name == "Stored Theme"

    generator_state = Micelio.Theme.TestGenerator.state(config)
    assert generator_state.calls == 0
  end

  test "generates and persists the daily theme when missing", %{
    config: config,
    server: server,
    prefix: prefix
  } do
    theme = Micelio.Theme.daily_theme(server: server)
    assert theme.name == "Test Signal"

    storage_state = Micelio.Theme.TestStorage.state(config)
    assert storage_state.puts == 1

    date = Date.utc_today()
    key = "#{prefix}/#{Date.to_iso8601(date)}.json"
    assert Map.has_key?(storage_state.data, key)

    generator_state = Micelio.Theme.TestGenerator.state(config)
    assert generator_state.calls == 1
  end

  test "renders CSS overrides for light and dark tokens" do
    theme = %{
      date: Date.utc_today(),
      name: "Palette",
      description: "Theme CSS rendering.",
      tokens: %{
        light: %{"--theme-ui-colors-primary" => "#112233"},
        dark: %{"--theme-ui-colors-primary" => "#ddeeff"}
      }
    }

    css = Micelio.Theme.css(theme)
    assert css =~ ":root"
    assert css =~ "@media (prefers-color-scheme: dark)"
    assert css =~ "--theme-ui-colors-primary: #112233;"
    assert css =~ "--theme-ui-colors-primary: #ddeeff;"
  end
end
