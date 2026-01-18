defmodule MicelioWeb.Plugs.RateLimitPlugTest do
  use MicelioWeb.ConnCase, async: true

  alias Boruta.Oauth.ResourceOwner
  alias Micelio.OAuth
  alias Micelio.OAuth.AccessTokens
  alias Micelio.OAuth.Clients
  alias MicelioWeb.Plugs.ApiAuthenticationPlug
  alias MicelioWeb.Plugs.RateLimitPlug

  test "rate limits unauthenticated requests", %{conn: conn} do
    opts =
      RateLimitPlug.init(
        limit: 1,
        window_ms: 60_000,
        bucket_prefix: unique_prefix(),
        skip_if_authenticated: true
      )

    conn = RateLimitPlug.call(conn, opts)
    refute conn.halted

    conn = RateLimitPlug.call(build_conn(), opts)
    assert conn.halted
    assert conn.status == 429
  end

  test "sets rate limit headers for unauthenticated requests", %{conn: conn} do
    opts =
      RateLimitPlug.init(
        limit: 2,
        window_ms: 60_000,
        bucket_prefix: unique_prefix(),
        skip_if_authenticated: true
      )

    conn = RateLimitPlug.call(conn, opts)

    assert get_resp_header(conn, "x-ratelimit-limit") == ["2"]
    assert get_resp_header(conn, "x-ratelimit-remaining") == ["1"]
  end

  test "returns retry-after header when rate limit is exceeded", %{conn: conn} do
    opts =
      RateLimitPlug.init(
        limit: 1,
        window_ms: 60_000,
        bucket_prefix: unique_prefix(),
        skip_if_authenticated: true
      )

    _conn = RateLimitPlug.call(conn, opts)

    conn = RateLimitPlug.call(build_conn(), opts)

    assert get_resp_header(conn, "retry-after") == ["60"]
    assert conn.halted
    assert conn.status == 429
  end

  test "skips rate limiting for authenticated requests", %{conn: conn} do
    {:ok, user} = Micelio.Accounts.get_or_create_user_by_email(unique_email())
    access_token = create_access_token(user)

    opts =
      RateLimitPlug.init(
        limit: 1,
        window_ms: 60_000,
        bucket_prefix: unique_prefix(),
        skip_if_authenticated: true
      )

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> ApiAuthenticationPlug.call([])
      |> RateLimitPlug.call(opts)

    refute conn.halted
    assert conn.assigns.current_user.id == user.id

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{access_token}")
      |> ApiAuthenticationPlug.call([])
      |> RateLimitPlug.call(opts)

    refute conn.halted
  end

  defp create_access_token(user) do
    {:ok, device_client} = OAuth.register_device_client(%{"name" => "hif"})
    {:ok, client} = Clients.get_client(device_client.client_id)

    params = %{
      client: client,
      scope: "",
      sub: to_string(user.id),
      resource_owner: %ResourceOwner{sub: to_string(user.id), username: user.email}
    }

    {:ok, token} = AccessTokens.create(params, refresh_token: true)
    Map.get(token, :value) || Map.get(token, :access_token)
  end

  defp unique_prefix do
    "api-test-#{System.unique_integer([:positive])}"
  end

  defp unique_email do
    "user#{System.unique_integer([:positive])}@example.com"
  end
end
