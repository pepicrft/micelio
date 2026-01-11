defmodule Micelio.Authorization.Repositories do
  @moduledoc false

  alias Micelio.Authorization

  def authorize(action, actor, repository) do
    Authorization.authorize(:"repository_#{action}", actor, repository)
  end
end
