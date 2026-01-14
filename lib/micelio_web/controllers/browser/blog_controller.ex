defmodule MicelioWeb.Browser.BlogController do
  use MicelioWeb, :controller

  alias Micelio.Blog
  alias MicelioWeb.PageMeta

  def index(conn, _params) do
    conn
    |> PageMeta.put(
      title_parts: ["Blog"],
      description:
        "Updates and insights from the Micelio team about building the future of agent-first software development.",
      canonical_url: url(~p"/blog")
    )
    |> render(:index, posts: Blog.all_posts())
  end

  def show(conn, %{"id" => id}) do
    post = Blog.get_post_by_id!(id)

    conn
    |> PageMeta.put(
      title_parts: [post.title, "Blog"],
      description: post.description,
      canonical_url: url(~p"/blog/#{post.id}"),
      type: "article",
      open_graph: %{"article:published_time" => Date.to_iso8601(post.date)}
    )
    |> render(:show, post: post)
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
