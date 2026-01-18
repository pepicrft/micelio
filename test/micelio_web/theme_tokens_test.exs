defmodule MicelioWeb.ThemeTokensTest do
  use ExUnit.Case, async: true

  test "activity graph colors use a light gray to green scale" do
    tokens = File.read!("assets/css/theme/tokens.css")

    assert tokens =~ "--theme-ui-colors-activity-0: oklch(0.96 0 0);"
    assert tokens =~ "--theme-ui-colors-activity-1: oklch(0.93 0.01 140);"
    assert tokens =~ "--theme-ui-colors-activity-2: oklch(0.86 0.06 140);"
    assert tokens =~ "--theme-ui-colors-activity-3: oklch(0.78 0.12 140);"
    assert tokens =~ "--theme-ui-colors-activity-4: oklch(0.7 0.18 140);"
  end

  test "profile activity graph styles use activity token base colors" do
    styles = File.read!("assets/css/routes/account_profile.css")

    assert styles =~ "--activity-graph-0: var(--theme-ui-colors-activity-0);"
    assert styles =~ "--activity-graph-1: var(--theme-ui-colors-activity-1);"
    assert styles =~ "--activity-graph-2: var(--theme-ui-colors-activity-2);"
    assert styles =~ "--activity-graph-3: var(--theme-ui-colors-activity-3);"
    assert styles =~ "--activity-graph-4: var(--theme-ui-colors-activity-4);"
    assert styles =~ ".activity-graph {\n  margin-top: 0;\n}"
  end
end
