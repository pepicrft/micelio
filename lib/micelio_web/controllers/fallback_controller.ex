defmodule MicelioWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """

  use MicelioWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: MicelioWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, {:bad_request, message}}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: MicelioWeb.ErrorJSON)
    |> render(:error, message: message)
  end

  def call(conn, {:error, {:invalid_state, message}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MicelioWeb.ErrorJSON)
    |> render(:error, message: message)
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: MicelioWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end
end
