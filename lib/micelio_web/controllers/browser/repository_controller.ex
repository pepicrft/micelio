defmodule MicelioWeb.Browser.RepositoryController do
  use MicelioWeb, :controller

  def show(conn, _params) do
    render(conn, :show)
  end
end
