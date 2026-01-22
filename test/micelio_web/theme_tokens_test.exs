defmodule MicelioWeb.ThemeTokensTest do
  use ExUnit.Case, async: true

  test "Turbopuffer-inspired theme colors are defined in tokens.css" do
    tokens = File.read!("assets/css/theme/tokens.css")

    # Light mode colors (Turbopuffer-inspired)
    assert tokens =~ "--theme-ui-colors-background: #f9fafc;"
    assert tokens =~ "--theme-ui-colors-text: #0f172a;"
    assert tokens =~ "--theme-ui-colors-accent: #fdba74;"
    assert tokens =~ "--theme-ui-colors-border: #e2e8f0;"
  end

  test "Turbopuffer activity graph colors" do
    tokens = File.read!("assets/css/theme/tokens.css")

    # Orange/amber activity colors
    assert tokens =~ "--theme-ui-colors-activity-0: #f1f5f9;"
    assert tokens =~ "--theme-ui-colors-activity-1: #fde68a;"
    assert tokens =~ "--theme-ui-colors-activity-2: #fdba74;"
    assert tokens =~ "--theme-ui-colors-activity-3: #fb923c;"
    assert tokens =~ "--theme-ui-colors-activity-4: #ea580c;"
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
