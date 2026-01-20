defmodule MicelioWeb.PageMetaTest do
  use ExUnit.Case, async: true

  alias MicelioWeb.PageMeta

  test "appends cache buster to custom og image urls" do
    meta = %PageMeta{
      title_parts: ["Demo"],
      canonical_url: "https://example.com/demo",
      open_graph: %{
        image: "https://assets.example.com/og/demo.png?foo=bar",
        cache_buster: "linkedin-8"
      }
    }

    og = PageMeta.open_graph(meta)
    image = Map.get(og, :image) || Map.get(og, "image") || Map.get(og, "og:image")

    refute Map.has_key?(og, :cache_buster)
    refute Map.has_key?(og, "cache_buster")

    assert image

    uri = URI.parse(image)
    assert %{"foo" => "bar", "v" => "linkedin-8"} = URI.decode_query(uri.query || "")
  end
end
