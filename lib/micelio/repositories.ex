defmodule Micelio.Repositories do
  alias Micelio.Repositories.Repository

  def repository(%{handle: handle}) do
    # TODO: Fetch in the DB
    {:ok, %Repository{handle: handle}}
  end
end
