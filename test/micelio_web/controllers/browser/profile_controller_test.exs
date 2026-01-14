defmodule MicelioWeb.Browser.ProfileControllerTest do
  use MicelioWeb.ConnCase, async: true

  setup :register_and_log_in_user

  test "shows profile page with devices link", %{conn: conn, user: user} do
    conn = get(conn, ~p"/account")
    html = html_response(conn, 200)

    assert html =~ "@#{user.account.handle}"
    assert html =~ "id=\"account-devices-link\""
  end

  test "shows navbar user link on authenticated pages", %{conn: conn, user: _user} do
    conn = get(conn, ~p"/account/devices")
    html = html_response(conn, 200)

    assert html =~ "class=\"navbar-user-avatar\""
    assert html =~ "id=\"navbar-user\""
    assert html =~ "href=\"/account\""
    assert html =~ "gravatar.com/avatar/"
  end
end
