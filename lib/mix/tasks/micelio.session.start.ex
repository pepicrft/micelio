defmodule Mix.Tasks.Micelio.Session.Start do
  use Mix.Task

  @shortdoc "Starts a Micelio session via the API (agent/CLI workflow)"
  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        switches: [
          session_id: :string,
          goal: :string,
          organization: :string,
          project: :string
        ],
        aliases: [s: :session_id, g: :goal, o: :organization, p: :project]
      )

    required!(opts, [:session_id, :goal, :organization, :project])

    case Micelio.CLI.Session.start_session(opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        Mix.shell().info("Session started: #{body["session"]["session_id"]}")

      {:ok, %Req.Response{status: status, body: body}} ->
        Mix.raise("Failed to start session (#{status}): #{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Failed to start session: #{inspect(reason)}")
    end
  end

  defp required!(opts, keys) do
    Enum.each(keys, fn key ->
      if is_nil(opts[key]) do
        Mix.raise("Missing required --#{key} option")
      end
    end)
  end
end
