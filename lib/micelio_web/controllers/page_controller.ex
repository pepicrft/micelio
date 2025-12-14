defmodule MicelioWeb.PageController do
  use MicelioWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
