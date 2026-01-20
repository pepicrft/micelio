defmodule MicelioWeb.OpenGraphImageTest do
  use ExUnit.Case, async: true

  alias MicelioWeb.OpenGraphImage
  alias MicelioWeb.PageMeta

  test "agent progress template renders commits and files changed" do
    attrs = %{
      "image_template" => "agent_progress",
      "title" => "Agent progress",
      "site_name" => "Micelio",
      "image_stats" => %{"commits" => 3, "files" => 12}
    }

    svg = OpenGraphImage.render_svg(attrs)

    assert svg =~ "COMMITS"
    assert svg =~ ">3<"
    assert svg =~ "FILES CHANGED"
    assert svg =~ ">12<"
  end

  test "agent progress template normalizes atom stats keys" do
    attrs = %{
      "image_template" => "agent_progress",
      "title" => "Agent progress",
      "site_name" => "Micelio",
      "image_stats" => %{commits: 2, files: 5}
    }

    svg = OpenGraphImage.render_svg(attrs)

    assert svg =~ "COMMITS"
    assert svg =~ ">2<"
    assert svg =~ "FILES CHANGED"
    assert svg =~ ">5<"
  end

  test "agent progress template renders snapshot header and defaults stats" do
    attrs = %{
      "image_template" => "agent_progress",
      "title" => "Agent progress",
      "site_name" => "Micelio"
    }

    svg = OpenGraphImage.render_svg(attrs)

    assert svg =~ "ACTIVITY SNAPSHOT"
    assert svg =~ "COMMITS"
    assert svg =~ ">0<"
    assert svg =~ "FILES CHANGED"
  end

  test "url appends cache buster to the query version" do
    meta = %PageMeta{
      canonical_url: "https://example.com/projects/demo",
      title_parts: ["Demo"],
      description: "Project demo",
      open_graph: %{cache_buster: "twitter-1"}
    }

    url = OpenGraphImage.url(meta)
    uri = URI.parse(url)

    assert %{"token" => token, "v" => version} = URI.decode_query(uri.query || "")
    assert token != ""
    assert String.starts_with?(uri.path || "", "/og/")
    assert String.ends_with?(version, "-twitter-1")
  end
end
