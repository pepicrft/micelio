defmodule MicelioWeb.Browser.OpenGraphImageController do
  use MicelioWeb, :controller

  alias MicelioWeb.OpenGraphImage

  def show(conn, %{"hash" => hash} = params) do
    etag = ~s|"#{hash}"|

    if Enum.member?(get_req_header(conn, "if-none-match"), etag) do
      conn
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_resp_header("etag", etag)
      |> send_resp(304, "")
    else
      token = Map.get(params, "token")

      case OpenGraphImage.fetch_or_create(hash, token) do
        {:ok, %{content_type: content_type, content: content}} ->
          conn
          |> put_resp_content_type(content_type)
          |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
          |> put_resp_header("etag", etag)
          |> send_resp(200, content)

        {:error, :invalid_token} ->
          send_resp(conn, 404, "Not found")

        {:error, :not_found} ->
          send_resp(conn, 404, "Not found")

        {:error, _reason} ->
          send_resp(conn, 500, "Error")
      end
    end
  end
end
