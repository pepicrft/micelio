defmodule Micelio.Blog do
  @moduledoc """
  The Blog context for managing blog posts using NimblePublisher.
  """

  alias Micelio.Blog.Post

  use NimblePublisher,
    build: Post,
    from: Application.app_dir(:micelio, "priv/posts/**/*.md"),
    as: :posts,
    highlighters: [:makeup_elixir, :makeup_erlang]

  # The @posts variable is first populated at compilation time.
  @posts Enum.sort_by(@posts, & &1.date, {:desc, Date})

  # Let's also get all tags
  @tags @posts |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()

  # And finally export them
  def all_posts, do: @posts
  def all_tags, do: @tags

  def recent_posts(count \\ 5) do
    Enum.take(all_posts(), count)
  end

  def get_post_by_id!(id) do
    Enum.find(all_posts(), &(&1.id == id)) ||
      raise "post with id=#{id} not found"
  end

  def get_posts_by_tag!(tag) do
    case Enum.filter(all_posts(), &(tag in &1.tags)) do
      [] -> raise "posts with tag=#{tag} not found"
      posts -> posts
    end
  end
end