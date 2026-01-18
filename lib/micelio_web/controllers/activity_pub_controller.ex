defmodule MicelioWeb.ActivityPubController do
  use MicelioWeb, :controller

  alias Micelio.Fediverse

  def webfinger(conn, %{"resource" => resource}) do
    with {:ok, handle} <- Fediverse.parse_webfinger_resource(resource),
         {:ok, _account} <- Fediverse.account_for_handle(handle) do
      conn
      |> put_resp_content_type("application/jrd+json")
      |> json(Fediverse.webfinger_response(handle))
    else
      _ ->
        send_resp(conn, :not_found, "")
    end
  end

  def webfinger(conn, _params), do: send_resp(conn, :bad_request, "")

  def actor(conn, %{"handle" => handle}) do
    with {:ok, account} <- Fediverse.account_for_handle(handle) do
      activity_pub_json(conn, Fediverse.actor_payload(account))
    else
      _ ->
        send_resp(conn, :not_found, "")
    end
  end

  def outbox(conn, %{"handle" => handle}) do
    with {:ok, _account} <- Fediverse.account_for_handle(handle) do
      activity_pub_json(conn, Fediverse.outbox_payload(handle))
    else
      _ ->
        send_resp(conn, :not_found, "")
    end
  end

  def followers(conn, %{"handle" => handle}) do
    with {:ok, account} <- Fediverse.account_for_handle(handle) do
      activity_pub_json(conn, Fediverse.followers_payload(account))
    else
      _ ->
        send_resp(conn, :not_found, "")
    end
  end

  def following(conn, %{"handle" => handle}) do
    with {:ok, account} <- Fediverse.account_for_handle(handle) do
      activity_pub_json(conn, Fediverse.following_payload(account))
    else
      _ ->
        send_resp(conn, :not_found, "")
    end
  end

  def inbox(conn, %{"handle" => handle} = params) do
    with {:ok, account} <- Fediverse.account_for_handle(handle),
         {:ok, _} <- Fediverse.process_inbox_activity(account, Map.delete(params, "handle")) do
      send_resp(conn, :accepted, "")
    else
      {:error, :bad_request} ->
        send_resp(conn, :bad_request, "")

      _ ->
        send_resp(conn, :not_found, "")
    end
  end

  defp activity_pub_json(conn, payload) do
    conn
    |> put_resp_content_type("application/activity+json")
    |> json(payload)
  end
end
