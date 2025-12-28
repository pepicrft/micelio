defmodule MicelioWeb.Router do
  use MicelioWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MicelioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :load_resources do
    plug MicelioWeb.ReesourcePlug, :load_account
    plug MicelioWeb.ReesourcePlug, :load_repository
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:micelio, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/admin" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MicelioWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  scope "/api", MicelioWeb.API do
    pipe_through :api

    get "/repositories", RepositoryController, :index
    get "/releases", ReleaseController, :index
  end

  scope "/", MicelioWeb.Browser do
    pipe_through([:browser, :load_resources])

    get "/", PageController, :home

    get "/:account", AccountController, :show
    get "/:account/:repository", RepositoryController, :show
  end
end
