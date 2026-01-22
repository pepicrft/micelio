defmodule MicelioWeb.Browser.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use MicelioWeb, :html
  use Gettext, backend: MicelioWeb.Gettext

  embed_templates "page_html/*"

  attr :projects, :list, required: true
  attr :page, :integer, required: true
  attr :has_more, :boolean, required: true

  def popular_projects_section(assigns) do
    ~H"""
    <section class="home-popular" id="popular-projects">
      <div class="home-popular-header">
        <h2 class="home-popular-title">{gettext("Popular projects")}</h2>
        <p class="home-popular-subtitle">{gettext("Explore what the community is building.")}</p>
      </div>

      <%= if Enum.empty?(@projects) do %>
        <p class="home-popular-empty" id="popular-projects-empty">
          {gettext("No public projects yet.")}
        </p>
      <% else %>
        <div class="home-popular-grid" id="popular-projects-list">
          <article
            :for={project <- @projects}
            class="home-popular-card"
            id={"popular-project-#{project.id}"}
          >
            <div class="home-popular-thumb" aria-hidden="true">
              <span>{String.upcase(String.slice(project.name || project.handle, 0, 1))}</span>
            </div>
            <div class="home-popular-body">
              <h3 class="home-popular-name">
                <a href={~p"/#{project.organization.account.handle}/#{project.handle}"}>
                  {project.name}
                </a>
              </h3>
              <p class="home-popular-handle">
                {project.organization.account.handle}/{project.handle}
              </p>
              <p class="home-popular-description">
                {project.description || gettext("No description yet.")}
              </p>
              <div class="home-popular-meta">
                <span class="home-popular-stars">
                  <svg
                    class="home-popular-icon"
                    aria-hidden="true"
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path stroke="none" d="M0 0h24v24H0z" fill="none" />
                    <path d="M3 12h4l3 8l4 -16l3 8h4" />
                  </svg>
                  <span class="sr-only">{gettext("Signals")}</span>
                  {project.star_count || 0}
                </span>
              </div>
            </div>
          </article>
        </div>

        <nav class="home-popular-pagination" aria-label={gettext("Popular projects pagination")}>
          <%= if @page > 1 do %>
            <a
              class="home-popular-page-link"
              id="popular-projects-prev"
              href={~p"/?popular_page=#{@page - 1}"}
            >
              {gettext("Previous")}
            </a>
          <% end %>
          <%= if @has_more do %>
            <a
              class="home-popular-page-link"
              id="popular-projects-next"
              href={~p"/?popular_page=#{@page + 1}"}
            >
              {gettext("Next")}
            </a>
          <% end %>
        </nav>
      <% end %>
    </section>
    """
  end
end
