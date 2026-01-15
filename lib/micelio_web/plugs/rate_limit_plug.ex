defmodule MicelioWeb.Plugs.RateLimitPlug do
  @moduledoc """
  Rate limiting plug using Hammer.

  Provides configurable rate limiting per IP address.
  """

  import Plug.Conn

  @behaviour Plug

  @default_limit 100
  @default_window_ms 60_000

  @impl true
  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms),
      bucket_prefix: Keyword.get(opts, :bucket_prefix, "api")
    }
  end

  @impl true
  def call(conn, %{limit: limit, window_ms: window_ms, bucket_prefix: prefix}) do
    key = bucket_key(conn, prefix)

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

  defp bucket_key(conn, prefix) do
    ip = get_client_ip(conn)
    "#{prefix}:#{ip}"
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
