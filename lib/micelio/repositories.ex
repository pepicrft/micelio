defmodule Micelio.Repositories do
  alias Micelio.Repositories.Repository

  @spec repository(%{handle: String.t()}) :: {:ok, Repository.t()} | {:error, :not_found}
  def repository(%{handle: handle}) do
    # TODO: Fetch in the DB
    {:ok, %Repository{handle: handle}}
  end
end
