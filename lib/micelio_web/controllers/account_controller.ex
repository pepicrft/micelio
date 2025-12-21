defmodule MicelioWeb.AccountController do
  use MicelioWeb, :controller

  def show(conn, params) do
    render(conn, :show)
  end
end
