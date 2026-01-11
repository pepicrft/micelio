defmodule MicelioWeb.API.DeviceAuthController do
  use MicelioWeb, :controller

  alias Micelio.OAuth

  def create(conn, params) do
    client_id = Map.get(params, "client_id")

    with %Micelio.OAuth.DeviceClient{} = client <- OAuth.get_device_client(client_id),
         :ok <- validate_client_secret(client, Map.get(params, "client_secret")),
         {:ok, grant} <- OAuth.create_device_grant(client, params) do
      conn
      |> put_status(:ok)
      |> json(device_auth_response(conn, grant))
    else
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_client", error_description: "Unknown client_id"})

      {:error, :invalid_client} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_client", error_description: "Invalid client credentials"})

      {:error, _reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_request", error_description: "Unable to create device grant"})
    end
  end

  defp device_auth_response(_conn, grant) do
    verification_uri = url(~p"/device/auth")

    %{
      device_code: grant.device_code,
      user_code: grant.user_code,
      verification_uri: verification_uri,
      verification_uri_complete: verification_uri <> "?" <> URI.encode_query(%{user_code: grant.user_code}),
      expires_in: DateTime.diff(grant.expires_at, DateTime.utc_now(), :second),
      interval: grant.interval
    }
  end

  defp validate_client_secret(%Micelio.OAuth.DeviceClient{confidential: false}, _secret), do: :ok

  defp validate_client_secret(%Micelio.OAuth.DeviceClient{client_secret: secret}, provided)
       when is_binary(provided) and byte_size(provided) == byte_size(secret) do
    if Plug.Crypto.secure_compare(provided, secret), do: :ok, else: {:error, :invalid_client}
  end

  defp validate_client_secret(_client, _provided), do: {:error, :invalid_client}
end
