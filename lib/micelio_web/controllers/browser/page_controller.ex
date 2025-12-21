defmodule MicelioWeb.Browser.PageController do
  use MicelioWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
