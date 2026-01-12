defmodule Micelio.CLI.Session do
  @moduledoc """
  Minimal CLI helpers for session start/land operations against the Micelio API.

  Authentication uses the `MICELIO_TOKEN` environment variable and defaults to
  `http://localhost:4000/api` for the API host unless `MICELIO_API_URL` is set.
  """

  @api_env "MICELIO_API_URL"
  @token_env "MICELIO_TOKEN"

  def start_session(opts) do
    base_url = System.get_env(@api_env) || "http://localhost:4000/api"
    token = fetch_token!()

    body = %{
      "session_id" => opts[:session_id],
      "goal" => opts[:goal],
      "organization" => opts[:organization],
      "project" => opts[:project],
      "conversation" => opts[:conversation] || [],
      "decisions" => opts[:decisions] || []
    }

    req =
      Req.new(
        url: "#{base_url}/sessions/start",
        headers: auth_headers(token),
        json: body
      )

    Req.request(req)
  end

  def land_session(opts) do
    base_url = System.get_env(@api_env) || "http://localhost:4000/api"
    token = fetch_token!()

    files =
      opts
      |> Keyword.get(:files, [])
      |> Enum.map(&build_file_payload/1)

    body =
      %{
        "session_id" => opts[:session_id],
        "conversation" => opts[:conversation] || [],
        "decisions" => opts[:decisions] || [],
        "files" => files
      }
      |> maybe_put_metadata(opts[:metadata])

    req =
      Req.new(
        url: "#{base_url}/sessions/#{opts[:session_id]}/land",
        headers: auth_headers(token),
        json: body
      )

    Req.request(req)
  end

  defp auth_headers(token), do: [{"authorization", "Bearer " <> token}]

  defp fetch_token! do
    System.get_env(@token_env) ||
      raise """
      Missing MICELIO_TOKEN.
      Export MICELIO_TOKEN with a valid bearer token to use the session CLI helpers.
      """
  end

  defp build_file_payload(%{path: path, change_type: change_type}) do
    content =
      case File.read(path) do
        {:ok, data} -> data
        {:error, reason} -> raise "Unable to read #{path}: #{inspect(reason)}"
      end

    %{
      "path" => path,
      "content" => content,
      "change_type" => change_type
    }
  end

  defp maybe_put_metadata(body, nil), do: body
  defp maybe_put_metadata(body, metadata), do: Map.put(body, "metadata", metadata)
end
