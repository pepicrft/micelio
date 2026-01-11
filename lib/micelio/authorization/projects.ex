defmodule Micelio.Authorization.Projects do
  @moduledoc false

  alias Micelio.Authorization

  def authorize(action, actor, project) do
    Authorization.authorize(:"project_#{action}", actor, project)
  end
end
