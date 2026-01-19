defmodule MicelioWeb.Browser.LegalControllerTest do
  use MicelioWeb.ConnCase, async: true

  @legacy_pages ["/privacy", "/terms", "/cookies", "/impressum"]

  test "legal page uses simplified responsibility disclaimer" do
    conn = build_conn() |> get("/legal")

    assert html_response(conn, 200) =~ "Legal"
    assert html_response(conn, 200) =~ "solely responsible for the content you host"
    assert html_response(conn, 200) =~ "essential cookies"
    assert html_response(conn, 200) =~ MicelioWeb.LegalInfo.legal_email()
    assert html_response(conn, 200) =~ MicelioWeb.LegalInfo.privacy_email()
  end

  test "legacy legal routes redirect to the consolidated page" do
    Enum.each(@legacy_pages, fn path ->
      conn = build_conn() |> get(path)

      assert redirected_to(conn) == "/legal"
    end)
  end
end
