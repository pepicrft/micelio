defmodule MicelioWeb.ActivityGraphComponentTest do
  use MicelioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias MicelioWeb.CoreComponents

  test "renders activity graph for provided counts" do
    today = Date.utc_today()

    html =
      render_component(&CoreComponents.activity_graph/1,
        activity_counts: %{today => 2},
        weeks: 1
      )

    assert html =~ "activity-graph"
    assert html =~ "aria-label=\"2 contributions\""
    assert html =~ "data-date=\"#{Date.to_iso8601(today)}\""
    assert html =~ "data-count=\"2\""
  end
end
