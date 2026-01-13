defmodule Mix.Tasks.Micelio.Rollups.Rebuild do
  @shortdoc "Rebuilds hif rollup indexes"

  @moduledoc """
  Rebuild hif rollup indexes for a project or all projects.

      mix micelio.rollups.rebuild --project <id> [--from 1] [--to 1000]
      mix micelio.rollups.rebuild --project <id> --from-head [--from 1]
      mix micelio.rollups.rebuild
  """

  use Mix.Task

  alias Micelio.Hif.RollupRebuilder
  alias Micelio.Projects

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} =
      OptionParser.parse(args,
        strict: [project: :string, from: :integer, to: :integer, from_head: :boolean]
      )

    case opts do
      %{project: project_id, from_head: true} ->
        from_position = Keyword.get(opts, :from, 1)
        _ = RollupRebuilder.rebuild_from_head(project_id, from_position)
        Mix.shell().info("Rebuilt rollups from head for project #{project_id}.")

      %{project: project_id} ->
        from_position = Keyword.get(opts, :from, 1)
        to_position = Keyword.get(opts, :to, from_position)
        _ = RollupRebuilder.rebuild(project_id, from_position, to_position)
        Mix.shell().info("Rebuilt rollups for project #{project_id}.")

      _ ->
        Projects.list_projects()
        |> Enum.each(fn project ->
          _ = RollupRebuilder.rebuild_from_head(project.id, 1)
        end)

        Mix.shell().info("Rebuilt rollups for all projects.")
    end
  end
end
