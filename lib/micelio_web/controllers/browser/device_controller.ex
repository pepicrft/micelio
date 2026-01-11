defmodule MicelioWeb.Browser.DeviceController do
  use MicelioWeb, :controller

  alias Micelio.OAuth

  def index(conn, _params) do
    sessions = OAuth.list_device_sessions_for_user(conn.assigns.current_user)
    render(conn, :index, sessions: sessions)
  end

  def delete(conn, %{"id" => id}) do
    case OAuth.get_device_session_for_user(conn.assigns.current_user, id) do
      nil ->
        conn
        |> put_flash(:error, "Device not found.")
        |> redirect(to: ~p"/account/devices")

      session ->
        {:ok, _} = OAuth.revoke_device_session(session)

        conn
        |> put_flash(:info, "Device access revoked.")
        |> redirect(to: ~p"/account/devices")
    end
  end
end
