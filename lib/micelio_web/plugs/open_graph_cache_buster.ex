defmodule MicelioWeb.Plugs.OpenGraphCacheBuster do
  @moduledoc """
  Adds a cache-buster key for social crawlers so OG image URLs can be invalidated per platform.
  """

  import Plug.Conn

  alias MicelioWeb.PageMeta

  @default_cache_busters %{
    "discord" => "1",
    "facebook" => "1",
    "linkedin" => "1",
    "pinterest" => "1",
    "slack" => "1",
    "telegram" => "1",
    "twitter" => "1"
  }

  @platform_user_agents [
    {"twitter", ~r/Twitterbot/i},
    {"linkedin", ~r/LinkedInBot|LinkedIn/i},
    {"facebook", ~r/facebookexternalhit|Facebot/i},
    {"slack", ~r/Slackbot/i},
    {"discord", ~r/Discordbot/i},
    {"telegram", ~r/TelegramBot/i},
    {"pinterest", ~r/Pinterest/i}
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = ensure_vary_user_agent(conn)

    with platform when is_binary(platform) <- crawler_platform(conn),
         cache_buster when is_binary(cache_buster) <- cache_buster_for(platform),
         cache_buster when cache_buster != "" <- cache_buster do
      PageMeta.put(conn, open_graph: %{cache_buster: "#{platform}-#{cache_buster}"})
    else
      _ -> conn
    end
  end

  defp crawler_platform(conn) do
    conn
    |> get_req_header("user-agent")
    |> List.first()
    |> case do
      nil ->
        nil

      user_agent ->
        Enum.find_value(@platform_user_agents, fn {platform, regex} ->
          if Regex.match?(regex, user_agent), do: platform
        end)
    end
  end

  defp cache_buster_for(platform) do
    cache_busters = normalize_cache_busters()

    Map.get(cache_busters, platform) ||
      Map.get(cache_busters, "default") ||
      Map.get(@default_cache_busters, platform) ||
      Map.get(@default_cache_busters, "default")
  end

  defp normalize_cache_busters do
    :micelio
    |> Application.get_env(:open_graph_cache_busters, %{})
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp ensure_vary_user_agent(conn) do
    existing =
      conn
      |> get_resp_header("vary")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if Enum.any?(existing, &(String.downcase(&1) == "user-agent")) do
      conn
    else
      updated =
        case existing do
          [] -> "User-Agent"
          _ -> Enum.join(existing ++ ["User-Agent"], ", ")
        end

      put_resp_header(conn, "vary", updated)
    end
  end
end
