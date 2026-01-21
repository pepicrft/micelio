defmodule MicelioWeb.ThemeTokensTest do
  use ExUnit.Case, async: true

  test "Chronicle theme colors and fonts are defined in tokens.css" do
    tokens = File.read!("assets/css/theme/tokens.css")

    # Chronicle light mode colors
    assert tokens =~ "--theme-ui-colors-background: #dfdfc1;"
    assert tokens =~ "--theme-ui-colors-text: #0b0d0b;"
    assert tokens =~ "--theme-ui-colors-primary: #0b0d0b;"

    # Typography
    assert tokens =~ ~s(--theme-ui-fonts-heading: "Playfair Display", Georgia, serif;)
    assert tokens =~ ~s(--theme-ui-fonts-body: "Inter", system-ui, sans-serif;)
    assert tokens =~ ~s(--theme-ui-fonts-mono: "JetBrains Mono", ui-monospace, monospace;)
  end

  test "activity graph colors use Gruvbox-inspired scale" do
    tokens = File.read!("assets/css/theme/tokens.css")

    assert tokens =~ "--theme-ui-colors-activity-0: #ebdbb2;"
    assert tokens =~ "--theme-ui-colors-activity-1: #b8bb26;"
    assert tokens =~ "--theme-ui-colors-activity-2: #98971a;"
    assert tokens =~ "--theme-ui-colors-activity-3: #79740e;"
    assert tokens =~ "--theme-ui-colors-activity-4: #5a5a0a;"
  end

  test "profile activity graph styles use theme tokens" do
    styles = File.read!("assets/css/routes/account_profile.css")

    assert styles =~ "--activity-graph-0: var(--theme-ui-colors-activity-0);"
    assert styles =~ "--activity-graph-1: var(--theme-ui-colors-activity-1);"
    assert styles =~ "--activity-graph-2: var(--theme-ui-colors-activity-2);"
    assert styles =~ "--activity-graph-3: var(--theme-ui-colors-activity-3);"
    assert styles =~ "--activity-graph-4: var(--theme-ui-colors-activity-4);"
    assert styles =~ ".activity-graph {\n  margin: 0;\n}"
  end
end
