defmodule MicelioWeb.Plugs.RateLimitPlug do
  @moduledoc """
  Rate limiting plug using Hammer.

  Provides configurable rate limiting per IP address and authenticated user.
  """

  @behaviour Plug

  import Plug.Conn

  @default_limit 100
  @default_window_ms 60_000

  @impl true
  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      bucket_prefix: Keyword.get(opts, :bucket_prefix, "api"),
      authenticated_limit: Keyword.get(opts, :authenticated_limit),
      authenticated_window_ms: Keyword.get(opts, :authenticated_window_ms),
      authenticated_bucket_prefix: Keyword.get(opts, :authenticated_bucket_prefix),
      skip_if_authenticated: Keyword.get(opts, :skip_if_authenticated, false)
    }
  end

  @impl true
  def call(conn, %{skip_if_authenticated: true} = opts) do
    if authenticated?(conn) do
      conn
    else
      apply_rate_limit(conn, opts, :unauthenticated)
    end
  end

  def call(conn, opts) do
    if authenticated?(conn) and not is_nil(opts.authenticated_limit) do
      apply_rate_limit(conn, opts, :authenticated)
    else
      apply_rate_limit(conn, opts, :unauthenticated)
    end
  end

  defp apply_rate_limit(conn, opts, :authenticated) do
    prefix = opts.authenticated_bucket_prefix || "#{opts.bucket_prefix}:auth"
    limit = opts.authenticated_limit
    window_ms = opts.authenticated_window_ms || opts.window_ms
    key = bucket_key(conn, prefix, :authenticated)

    apply_rate_limit_with_key(conn, limit, window_ms, key)
  end

  defp apply_rate_limit(
         conn,
         %{limit: limit, window_ms: window_ms, bucket_prefix: prefix},
         :unauthenticated
       ) do
    key = bucket_key(conn, prefix, :unauthenticated)

    apply_rate_limit_with_key(conn, limit, window_ms, key)
  end

  defp apply_rate_limit_with_key(conn, limit, window_ms, key) do
    case Hammer.check_rate(key, window_ms, limit) do
      {:allow, count} ->
        conn
        |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", Integer.to_string(max(0, limit - count)))

      {:deny, _limit} ->
        conn
        |> put_resp_header("x-ratelimit-limit", Integer.to_string(limit))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_resp_header("retry-after", Integer.to_string(div(window_ms, 1000)))
        |> send_resp(429, "Rate limit exceeded. Please try again later.")
        |> halt()
    end
  end

  defp authenticated?(conn) do
    not is_nil(conn.assigns[:current_user])
  end

  defp bucket_key(conn, prefix, :authenticated) do
    case conn.assigns[:current_user] do
      %{id: user_id} -> "#{prefix}:user:#{user_id}"
      _ -> bucket_key(conn, prefix, :unauthenticated)
    end
  end

  defp bucket_key(conn, prefix, :unauthenticated) do
    ip = get_client_ip(conn)
    "#{prefix}:ip:#{ip}"
  end

  defp get_client_ip(conn) do
    forwarded_for =
      conn
      |> get_req_header("x-forwarded-for")
      |> List.first()

    case forwarded_for do
      nil ->
        conn.remote_ip |> :inet.ntoa() |> to_string()

      value ->
        value
        |> String.split(",")
        |> List.first()
        |> String.trim()
    end
  end
end
