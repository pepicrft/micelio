defmodule MicelioWeb.ThemeTokensTest do
  use ExUnit.Case, async: true

  test "GitHub-style theme colors are defined in tokens.css" do
    tokens = File.read!("assets/css/theme/tokens.css")

    # Light mode colors
    assert tokens =~ "--theme-ui-colors-background: #ffffff;"
    assert tokens =~ "--theme-ui-colors-text: #1f2328;"
    assert tokens =~ "--theme-ui-colors-accent: #0969da;"
    assert tokens =~ "--theme-ui-colors-border: #d1d9e0;"
  end

  test "GitHub activity graph colors" do
    tokens = File.read!("assets/css/theme/tokens.css")

    assert tokens =~ "--theme-ui-colors-activity-0: #ebedf0;"
    assert tokens =~ "--theme-ui-colors-activity-1: #9be9a8;"
    assert tokens =~ "--theme-ui-colors-activity-2: #40c463;"
    assert tokens =~ "--theme-ui-colors-activity-3: #30a14e;"
    assert tokens =~ "--theme-ui-colors-activity-4: #216e39;"
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
