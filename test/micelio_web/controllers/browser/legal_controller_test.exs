defmodule MicelioWeb.Browser.LegalControllerTest do
  use MicelioWeb.ConnCase, async: true

  @legal_pages [
    {"/privacy", "Privacy Policy"},
    {"/terms", "Terms of Service"},
    {"/cookies", "Cookie Policy"},
    {"/impressum", "Impressum"}
  ]

  test "legal pages use simplified responsibility disclaimer" do
    Enum.each(@legal_pages, fn {path, title} ->
      conn = build_conn() |> get(path)

      assert html_response(conn, 200) =~ title
      assert html_response(conn, 200) =~ "solely responsible for the content you host"
    end)
  end

  test "cookies page states essential cookie usage" do
    conn = build_conn() |> get("/cookies")

    assert html_response(conn, 200) =~ "essential cookies"
    assert html_response(conn, 200) =~ "We do not use analytics"
  end
end
