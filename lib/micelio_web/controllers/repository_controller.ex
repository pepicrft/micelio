defmodule MicelioWeb.RepositoryController do
  use MicelioWeb, :controller

  def show(conn, _params) do
    render(conn, :show)
  end
end
