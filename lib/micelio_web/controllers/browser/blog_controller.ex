defmodule MicelioWeb.Browser.BlogController do
  use MicelioWeb, :controller

  alias Micelio.Blog

  def index(conn, _params) do
    render(conn, :index, posts: Blog.all_posts())
  end

  def show(conn, %{"id" => id}) do
    post = Blog.get_post_by_id!(id)
    render(conn, :show, post: post)
  end

  def rss(conn, _params) do
    posts = Blog.recent_posts(10)

    conn
    |> put_resp_content_type("application/rss+xml")
    |> render(:rss, posts: posts, layout: false)
  end

  def atom(conn, _params) do
    posts = Blog.recent_posts(10)

    conn
    |> put_resp_content_type("application/atom+xml")
    |> render(:atom, posts: posts, layout: false)
  end
end