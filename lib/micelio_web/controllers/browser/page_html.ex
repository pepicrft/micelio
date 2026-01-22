defmodule MicelioWeb.Browser.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use MicelioWeb, :html
  use Gettext, backend: MicelioWeb.Gettext

  embed_templates "page_html/*"

  attr :projects, :list, required: true
  attr :current_user, :any, default: nil
  attr :current_path, :string, default: "/"
  attr :page, :integer, required: true
  attr :has_more, :boolean, required: true

  def popular_projects_section(assigns) do
    assigns =
      assign(assigns,
        :title,
        if(assigns.current_user,
          do: gettext("Recent projects"),
          else: gettext("Popular projects")
        )
      )

    assigns =
      assign(assigns,
        :subtitle,
        if(assigns.current_user,
          do: gettext("Projects you've worked on recently."),
          else: gettext("Explore what the community is building.")
        )
      )

    assigns =
      assign(assigns,
        :empty_message,
        if(assigns.current_user,
          do: gettext("No recent projects yet."),
          else: gettext("No public projects yet.")
        )
      )

    ~H"""
    <section class="home-popular" id="popular-projects">
      <div class="home-popular-header">
        <h2 class="home-popular-title">{@title}</h2>
        <p class="home-popular-subtitle">{@subtitle}</p>
      </div>

      <%= if Enum.empty?(@projects) do %>
        <p class="home-popular-empty" id="popular-projects-empty">
          {@empty_message}
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
                <% return_to = @current_path || "/" %>
                <%= if @current_user do %>
                  <form
                    class="home-popular-pulse-form"
                    action={~p"/#{project.organization.account.handle}/#{project.handle}/star"}
                    method="post"
                  >
                    <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
                    <input type="hidden" name="star[return_to]" value={return_to} />
                    <button
                      type="submit"
                      class={[
                        "project-star-toggle",
                        "home-popular-pulse-toggle",
                        project.starred && "is-starred"
                      ]}
                      aria-pressed={project.starred || false}
                      aria-label={if project.starred, do: gettext("Unpulse"), else: gettext("Pulse")}
                      title={if project.starred, do: gettext("Unpulse"), else: gettext("Pulse")}
                    >
                      <span class="sr-only">
                        <%= if project.starred do %>
                          <%= gettext("Unpulse") %>
                        <% else %>
                          <%= gettext("Pulse") %>
                        <% end %>
                      </span>
                      <%= if project.starred do %>
                        <svg
                          class="project-pulse-toggle-icon"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          stroke-width="1.5"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          aria-hidden="true"
                        >
                          <path d="M3 12h4l3 8l4-16l3 8h4" />
                        </svg>
                      <% else %>
                        <svg
                          class="project-pulse-toggle-icon"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          stroke-width="1.5"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          aria-hidden="true"
                        >
                          <path d="M3 12h4l3 8l4-16l3 8h4" />
                        </svg>
                      <% end %>
                      <span class="project-star-count">
                        {project.star_count || 0}
                      </span>
                    </button>
                  </form>
                <% else %>
                  <div class="home-popular-pulse-static">
                    <span class="home-popular-pulse-icon" aria-hidden="true">
                      <svg
                        class="project-pulse-toggle-icon"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="1.5"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      >
                        <path d="M3 12h4l3 8l4-16l3 8h4" />
                      </svg>
                    </span>
                    <span class="sr-only">{gettext("Pulses")}</span>
                    <span class="home-popular-pulse-count">
                      {project.star_count || 0}
                    </span>
                  </div>
                <% end %>
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
