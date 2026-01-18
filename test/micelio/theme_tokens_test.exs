defmodule Micelio.ThemeTokensTest do
  use ExUnit.Case, async: true

  defp css_path(path) do
    Path.expand(Path.join(["../..", path]), __DIR__)
  end

  test "activity graph uses a light gray base color" do
    css = File.read!(css_path("assets/css/theme/tokens.css"))

    assert css =~ "--theme-ui-colors-activity-0: oklch(0.96 0 0);"
  end
end
