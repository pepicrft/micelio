defmodule MicelioWeb.ErrorBoundaryComponentTest do
  use MicelioWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Micelio.ErrorBoundary
  alias Micelio.Errors.Error
  alias Micelio.Repo

  test "renders inner content when no error is raised" do
    html =
      render_component(&ErrorBoundary.error_boundary/1, id: "boundary", retry_path: "/retry") do
        "All good"
      end

    assert html =~ "All good"
    refute html =~ "error-boundary-title"
  end

  test "captures render exceptions and shows fallback" do
    Repo.delete_all(Error)

    html =
      render_component(&ErrorBoundary.error_boundary/1,
        id: "boundary",
        retry_path: "/retry",
        capture_async: false,
        context: %{route: "/boom", params: %{"oops" => "1"}}
      ) do
        raise "boom"
      end

    assert html =~ "Something went wrong"
    assert html =~ "Retry"

    [error] = Repo.all(Error)
    assert error.kind == :liveview_crash
    assert error.message =~ "boom"
    assert error.context["route"] == "/boom"
    assert error.context["params"]["oops"] == "1"
  end

  test "renders fallback for exits and captures the reason" do
    Repo.delete_all(Error)

    html =
      render_component(&ErrorBoundary.error_boundary/1,
        id: "boundary-exit",
        retry_path: "/retry",
        capture_async: false,
        context: %{route: "/exit", params: %{}}
      ) do
        exit(:boom)
      end

    assert html =~ "Something went wrong"

    [error] = Repo.all(Error)
    assert error.kind == :liveview_crash
    assert error.message =~ "LiveView exited"
  end
end
