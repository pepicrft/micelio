defmodule MicelioWeb.Browser.PasskeyController do
  use MicelioWeb, :controller

  alias Micelio.Accounts
  alias Micelio.Auth.Passkeys

  def registration_options(conn, _params) do
    challenge = Passkeys.generate_challenge()

    conn
    |> put_session(:passkey_registration_challenge, Base.url_encode64(challenge, padding: false))
    |> json(Passkeys.registration_options(conn.assigns.current_user, challenge))
  end

  def register(conn, params) do
    with {:ok, challenge} <- fetch_challenge(conn, :passkey_registration_challenge),
         {:ok, result} <- Passkeys.verify_registration(params, challenge),
         {:ok, passkey} <-
           Accounts.create_passkey(conn.assigns.current_user, %{
             credential_id: result.credential_id,
             public_key: result.public_key,
             sign_count: result.sign_count,
             name: passkey_name(params)
           }) do
      conn
      |> delete_session(:passkey_registration_challenge)
      |> json(%{status: "ok", passkey_id: passkey.id})
    else
      {:error, :missing_challenge} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Passkey registration expired."})

      _ ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Unable to register passkey."})
    end
  end

  def authentication_options(conn, _params) do
    challenge = Passkeys.generate_challenge()

    conn
    |> put_session(
      :passkey_authentication_challenge,
      Base.url_encode64(challenge, padding: false)
    )
    |> json(Passkeys.authentication_options(challenge))
  end

  def authenticate(conn, params) do
    with {:ok, challenge} <- fetch_challenge(conn, :passkey_authentication_challenge),
         {:ok, credential_id} <- Passkeys.credential_id_from_params(params),
         %Accounts.Passkey{} = passkey <- Accounts.get_passkey_by_credential_id(credential_id),
         {:ok, result} <- Passkeys.verify_authentication(params, challenge, passkey),
         {:ok, _passkey} <-
           Accounts.update_passkey_usage(passkey, %{
             sign_count: result.sign_count,
             last_used_at: DateTime.utc_now()
           }) do
      conn
      |> delete_session(:passkey_authentication_challenge)
      |> put_session(:user_id, passkey.user_id)
      |> json(%{status: "ok", redirect_to: ~p"/"})
    else
      {:error, :missing_challenge} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Passkey login expired."})

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Unable to authenticate with passkey."})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Accounts.get_passkey(id) do
      %Accounts.Passkey{} = passkey when passkey.user_id == conn.assigns.current_user.id ->
        {:ok, _} = Accounts.delete_passkey(passkey)
        json(conn, %{status: "ok"})

      _ ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Passkey not found."})
    end
  end

  defp fetch_challenge(conn, key) do
    case get_session(conn, key) do
      nil -> {:error, :missing_challenge}
      challenge -> {:ok, challenge}
    end
  end

  defp passkey_name(%{"name" => name}) when is_binary(name) do
    name = String.trim(name)

    if name == "" do
      default_passkey_name()
    else
      String.slice(name, 0, 64)
    end
  end

  defp passkey_name(_), do: default_passkey_name()

  defp default_passkey_name do
    date = Date.utc_today() |> Date.to_iso8601()
    "Passkey #{date}"
  end
end
