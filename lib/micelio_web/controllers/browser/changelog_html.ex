defmodule MicelioWeb.Browser.ChangelogHTML do
  use MicelioWeb, :html

  embed_templates "changelog_html/*"

  @doc """
  Renders a changelog entry card.
  """
  attr :entry, :map, required: true

  def entry_card(assigns) do
    ~H"""
    <article class="changelog-entry">
      <header class="changelog-entry-header">
        <h2 class="changelog-entry-title">
          <.link navigate={~p"/changelog/#{@entry.id}"}>
            {@entry.title}
          </.link>
        </h2>
        <div class="changelog-entry-meta">
          <time datetime={Date.to_iso8601(@entry.date)}>
            {Calendar.strftime(@entry.date, "%B %d, %Y")}
          </time>
          <span class="changelog-entry-version">
            v{@entry.version}
          </span>
          <%= for category <- @entry.categories do %>
            <.link
              navigate={~p"/changelog/category/#{category}"}
              class="changelog-entry-category"
            >
              {category}
            </.link>
          <% end %>
        </div>
      </header>

      <div class="changelog-entry-description">
        {@entry.description}
      </div>
    </article>
    """
  end

  @doc """
  Formats a date for display.
  """
  def format_date(date) do
    Calendar.strftime(date, "%B %d, %Y")
  end
end
