defmodule MicelioWeb.Browser.ChangelogHTML do
  use MicelioWeb, :html

  embed_templates "changelog_html/*"

  @doc """
  Renders a changelog entry card.
  """
  attr :entry, :map, required: true
  
  def entry_card(assigns) do
    ~H"""
    <article class="bg-white shadow-sm rounded-lg p-6 mb-6 border border-gray-200">
      <header class="mb-4">
        <div class="flex items-center justify-between mb-2">
          <h2 class="text-xl font-semibold text-gray-900">
            <.link navigate={~p"/changelog/#{@entry.id}"} class="hover:text-blue-600">
              <%= @entry.title %>
            </.link>
          </h2>
          <span class="text-sm text-gray-500 font-mono bg-gray-100 px-2 py-1 rounded">
            v<%= @entry.version %>
          </span>
        </div>
        <div class="flex items-center gap-4 text-sm text-gray-600">
          <time datetime={Date.to_iso8601(@entry.date)} class="flex items-center gap-1">
            <.icon name="hero-calendar-days" class="w-4 h-4" />
            {Calendar.strftime(@entry.date, "%B %d, %Y")}
          </time>
          <div class="flex items-center gap-1">
            <.icon name="hero-tag" class="w-4 h-4" />
            <div class="flex gap-1">
              <%= for category <- @entry.categories do %>
                <.link 
                  navigate={~p"/changelog/category/#{category}"} 
                  class="px-2 py-0.5 bg-blue-100 text-blue-800 rounded-full text-xs hover:bg-blue-200"
                >
                  <%= category %>
                </.link>
              <% end %>
            </div>
          </div>
        </div>
      </header>
      
      <div class="prose prose-sm max-w-none text-gray-700">
        <%= @entry.description %>
      </div>
      
      <footer class="mt-4 pt-4 border-t border-gray-100">
        <.link 
          navigate={~p"/changelog/#{@entry.id}"} 
          class="text-blue-600 hover:text-blue-800 text-sm font-medium"
        >
          Read full changelog →
        </.link>
      </footer>
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