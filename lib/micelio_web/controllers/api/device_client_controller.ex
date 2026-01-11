defmodule MicelioWeb.API.DeviceClientController do
  use MicelioWeb, :controller

  alias Micelio.OAuth

  def create(conn, params) do
    attrs = Map.take(params, ["name"])

    case OAuth.register_device_client(attrs) do
      {:ok, client} ->
        conn
        |> put_status(:created)
        |> json(%{
          client_id: client.client_id,
          client_secret: client.client_secret,
          device_authorization_endpoint: device_authorization_endpoint(conn),
          token_endpoint: device_token_endpoint(conn)
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid_client", details: changeset_errors(changeset)})
    end
  end

  defp device_authorization_endpoint(_conn) do
    url(~p"/api/device/auth")
  end

  defp device_token_endpoint(_conn) do
    url(~p"/api/device/token")
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
