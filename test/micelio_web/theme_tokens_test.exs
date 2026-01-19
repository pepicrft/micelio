defmodule MicelioWeb.ThemeTokensTest do
  use ExUnit.Case, async: true

  test "activity graph colors use a light gray to green scale" do
    tokens = File.read!("assets/css/theme/tokens.css")

    assert tokens =~ "--theme-ui-colors-activity-0: #ebedf0;"
    assert tokens =~ "--theme-ui-colors-activity-1: #9be9a8;"
    assert tokens =~ "--theme-ui-colors-activity-2: #40c463;"
    assert tokens =~ "--theme-ui-colors-activity-3: #30a14e;"
    assert tokens =~ "--theme-ui-colors-activity-4: #216e39;"
  end

  test "profile activity graph styles use activity token base colors" do
    styles = File.read!("assets/css/routes/account_profile.css")

    assert styles =~ "--activity-graph-0: #ebedf0;"
    assert styles =~ "--activity-graph-1: #9be9a8;"
    assert styles =~ "--activity-graph-2: #40c463;"
    assert styles =~ "--activity-graph-3: #30a14e;"
    assert styles =~ "--activity-graph-4: #216e39;"
    assert styles =~ ".activity-graph {\n  margin: 0;\n}"
  end
end
