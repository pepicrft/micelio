defmodule MicelioWeb.API.DeviceTokenController do
  use MicelioWeb, :controller

  alias Micelio.OAuth

  @device_grant_type "urn:ietf:params:oauth:grant-type:device_code"

  def create(conn, %{"grant_type" => @device_grant_type} = params) do
    client_id = params["client_id"]
    device_code = params["device_code"]

    with %Micelio.OAuth.DeviceClient{} = client <- OAuth.get_device_client(client_id),
         :ok <- validate_client_secret(client, Map.get(params, "client_secret")),
         {:ok, token, _session} <- OAuth.exchange_device_code(client.client_id, device_code) do
      conn
      |> put_status(:ok)
      |> json(token_response(token, client.client_id))
    else
      nil ->
        token_error(conn, "invalid_client", "Unknown client_id.", :unauthorized)

      {:error, :invalid_client} ->
        token_error(conn, "invalid_client", "Invalid client credentials.", :unauthorized)

      {:error, :authorization_pending} ->
        token_error(conn, "authorization_pending", "The device authorization is pending.")

      {:error, :slow_down} ->
        token_error(conn, "slow_down", "Slow down polling and try again.")

      {:error, :expired_token} ->
        token_error(conn, "expired_token", "The device code has expired.")

      {:error, :invalid_grant} ->
        token_error(conn, "invalid_grant", "Invalid device code.")

      {:error, _reason} ->
        token_error(conn, "invalid_request", "Unable to exchange the device code.")
    end
  end

  def create(conn, params) do
    MicelioWeb.Oauth.TokenController.token(conn, params)
  end

  defp token_response(token, client_id) do
    access_token = Map.get(token, :value) || Map.get(token, :access_token)
    refresh_token = Map.get(token, :refresh_token)
    expires_in = Map.get(token, :expires_in) || client_access_token_ttl(client_id)

    %{
      token_type: "Bearer",
      access_token: access_token,
      expires_in: expires_in || 3600,
      refresh_token: refresh_token
    }
  end

  defp client_access_token_ttl(client_id) do
    case OAuth.get_device_client(client_id) do
      %Micelio.OAuth.DeviceClient{access_token_ttl: access_token_ttl} -> access_token_ttl
      _ -> nil
    end
  end

  defp token_error(conn, error, description, status \\ :bad_request) do
    conn
    |> put_status(status)
    |> json(%{error: error, error_description: description})
  end

  defp validate_client_secret(%Micelio.OAuth.DeviceClient{confidential: false}, _secret), do: :ok

  defp validate_client_secret(%Micelio.OAuth.DeviceClient{client_secret: secret}, provided)
       when is_binary(provided) and byte_size(provided) == byte_size(secret) do
    if Plug.Crypto.secure_compare(provided, secret), do: :ok, else: {:error, :invalid_client}
  end

  defp validate_client_secret(_client, _provided), do: {:error, :invalid_client}
end
