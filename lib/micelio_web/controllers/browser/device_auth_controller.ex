defmodule MicelioWeb.Browser.DeviceAuthController do
  use MicelioWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Micelio.OAuth

  def new(conn, params) do
    user_code = Map.get(params, "user_code", "")
    form = to_form(%{"user_code" => user_code}, as: :device)

    render(conn, :new, form: form)
  end

  def verify(conn, %{"device" => %{"user_code" => user_code}}) do
    case OAuth.approve_device_grant(user_code, conn.assigns.current_user) do
      {:ok, grant} ->
        render(conn, :success, grant: grant)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "That code was not found. Please check and try again.")
        |> render(:new, form: to_form(%{"user_code" => user_code}, as: :device))

      {:error, :expired_token} ->
        conn
        |> put_flash(:error, "This device code has expired. Please start again.")
        |> render(:new, form: to_form(%{"user_code" => user_code}, as: :device))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Unable to approve this device right now.")
        |> render(:new, form: to_form(%{"user_code" => user_code}, as: :device))
    end
  end
end
