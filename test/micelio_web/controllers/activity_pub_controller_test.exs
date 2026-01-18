defmodule MicelioWeb.ActivityPubControllerTest do
  use MicelioWeb.ConnCase, async: true

  alias Micelio.Accounts
  alias Micelio.Fediverse

  defp create_handle do
    email = "ap#{System.unique_integer()}@example.com"
    {:ok, user} = Accounts.get_or_create_user_by_email(email)
    user.account.handle
  end

  test "webfinger returns actor link", %{conn: conn} do
    handle = create_handle()
    resource = Fediverse.webfinger_subject(handle)

    conn = get(conn, ~p"/.well-known/webfinger?#{%{resource: resource}}")
    response = json_response(conn, 200)

    assert response["subject"] == resource
    [link] = response["links"]
    assert link["rel"] == "self"
    assert link["type"] == "application/activity+json"
    assert link["href"] == Fediverse.actor_url(handle)
  end

  test "actor returns activitypub payload", %{conn: conn} do
    handle = create_handle()

    conn = get(conn, ~p"/ap/actors/#{handle}")
    response = json_response(conn, 200)

    assert response["id"] == Fediverse.actor_url(handle)
    assert response["preferredUsername"] == handle
    assert response["inbox"] == Fediverse.inbox_url(handle)
    assert response["outbox"] == Fediverse.outbox_url(handle)
    assert response["followers"] == Fediverse.followers_url(handle)
    assert response["following"] == Fediverse.following_url(handle)
    assert "https://www.w3.org/ns/activitystreams" in response["@context"]
  end

  test "outbox is an empty ordered collection", %{conn: conn} do
    handle = create_handle()

    conn = get(conn, ~p"/ap/actors/#{handle}/outbox")
    response = json_response(conn, 200)

    assert response["type"] == "OrderedCollection"
    assert response["totalItems"] == 0
    assert response["orderedItems"] == []
  end

  test "inbox accepts activities", %{conn: conn} do
    handle = create_handle()

    conn =
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> post(~p"/ap/actors/#{handle}/inbox", %{
        "type" => "Follow",
        "actor" => "https://example.com/users/alice"
      })

    assert conn.status == 202
  end

  test "follow activity is stored in followers collection", %{conn: conn} do
    handle = create_handle()
    actor = "https://example.com/users/alice"

    conn =
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> post(~p"/ap/actors/#{handle}/inbox", %{
        "type" => "Follow",
        "actor" => actor
      })

    assert conn.status == 202

    conn = get(conn, ~p"/ap/actors/#{handle}/followers")
    response = json_response(conn, 200)

    assert response["totalItems"] == 1
    assert response["orderedItems"] == [actor]
  end

  test "undo follow removes follower", %{conn: conn} do
    handle = create_handle()
    actor = "https://example.com/users/alice"

    conn =
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> post(~p"/ap/actors/#{handle}/inbox", %{
        "type" => "Follow",
        "actor" => actor
      })

    assert conn.status == 202

    conn =
      conn
      |> put_req_header("content-type", "application/activity+json")
      |> post(~p"/ap/actors/#{handle}/inbox", %{
        "type" => "Undo",
        "actor" => actor,
        "object" => %{"type" => "Follow"}
      })

    assert conn.status == 202

    conn = get(conn, ~p"/ap/actors/#{handle}/followers")
    response = json_response(conn, 200)

    assert response["totalItems"] == 0
    assert response["orderedItems"] == []
  end

  test "unknown actor returns 404", %{conn: conn} do
    conn = get(conn, ~p"/ap/actors/unknown")
    assert conn.status == 404
  end
end
