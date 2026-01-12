defmodule Mix.Tasks.Micelio.Session.Land do
  use Mix.Task

  @shortdoc "Lands a Micelio session via the API (uploads changes and marks landed)"
  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        switches: [
          session_id: :string,
          file: :keep,
          metadata: :string
        ],
        aliases: [s: :session_id, f: :file]
      )

    required!(opts, [:session_id])

    file_payloads =
      opts
      |> Keyword.get_values(:file)
      |> Enum.map(&parse_file_option/1)

    metadata = parse_metadata(opts[:metadata])

    request_opts =
      opts
      |> Keyword.put(:files, file_payloads)
      |> Keyword.put(:metadata, metadata)

    case Micelio.CLI.Session.land_session(request_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        Mix.shell().info("Session landed: #{body["session"]["session_id"]}")

      {:ok, %Req.Response{status: status, body: body}} ->
        Mix.raise("Failed to land session (#{status}): #{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Failed to land session: #{inspect(reason)}")
    end
  end

  defp parse_file_option(value) do
    [path, change_type] =
      case String.split(value, ":", parts: 2) do
        [p, type] -> [p, type]
        [p] -> [p, "modified"]
      end

    %{path: path, change_type: change_type}
  end

  defp parse_metadata(nil), do: nil

  defp parse_metadata(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(fn entry ->
      case String.split(entry, "=", parts: 2) do
        [k, v] -> {k, v}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp required!(opts, keys) do
    Enum.each(keys, fn key ->
      if is_nil(opts[key]) do
        Mix.raise("Missing required --#{key} option")
      end
    end)
  end
end
