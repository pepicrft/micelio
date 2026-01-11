defmodule MicelioWeb.Router do
  use MicelioWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MicelioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MicelioWeb.AuthenticationPlug
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug MicelioWeb.RequireAuthPlug
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

    # OAuth2 Device Authentication Flow
    post "/device/auth", DeviceAuthController, :create
    post "/device/token", DeviceTokenController, :create
    post "/device/client", DeviceClientController, :create
  end

  scope "/device", MicelioWeb.API do
    pipe_through :api

    post "/register", DeviceClientController, :create
    post "/auth", DeviceAuthController, :create
    post "/token", DeviceTokenController, :create
  end

  # Blog routes (public)
  scope "/blog", MicelioWeb.Browser do
    pipe_through :browser

    get "/", BlogController, :index
    get "/rss", BlogController, :rss
    get "/atom", BlogController, :atom
    get "/:id", BlogController, :show
  end

  # Changelog routes (public)
  scope "/changelog", MicelioWeb.Browser do
    pipe_through :browser

    get "/", ChangelogController, :index
    get "/rss", ChangelogController, :rss
    get "/atom", ChangelogController, :atom
    get "/category/:category", ChangelogController, :category
    get "/version/:version", ChangelogController, :version
    get "/:id", ChangelogController, :show
  end

  # Auth routes (before catch-all)
  scope "/auth", MicelioWeb.Browser do
    pipe_through :browser

    get "/login", AuthController, :new
    post "/login", AuthController, :create
    get "/sent", AuthController, :sent
    get "/verify/:token", AuthController, :verify
    delete "/logout", AuthController, :delete
  end

  scope "/device", MicelioWeb.Browser do
    pipe_through [:browser, :require_auth]

    get "/auth", DeviceAuthController, :new
    post "/auth/verify", DeviceAuthController, :verify
  end

  # Project routes (require authentication)
  scope "/projects", MicelioWeb.Browser do
    pipe_through [:browser, :require_auth]

    live_session :projects, on_mount: {MicelioWeb.LiveAuth, :require_auth} do
      live "/", MicelioWeb.ProjectLive.Index, :index
      live "/new", MicelioWeb.ProjectLive.New, :new
      live "/:organization_handle/:project_handle/edit", MicelioWeb.ProjectLive.Edit, :edit
      live "/:organization_handle/:project_handle", MicelioWeb.ProjectLive.Show, :show
    end
  end

  # Organization routes (require authentication)
  scope "/organizations", MicelioWeb.Browser do
    pipe_through [:browser, :require_auth]

    get "/new", OrganizationController, :new
    post "/", OrganizationController, :create
  end

  scope "/account", MicelioWeb.Browser do
    pipe_through [:browser, :require_auth]

    get "/devices", DeviceController, :index
    delete "/devices/:id", DeviceController, :delete
  end

  scope "/", MicelioWeb.Browser do
    pipe_through([:browser, :load_resources])

    get "/", PageController, :home

    get "/:account", AccountController, :show
    get "/:account/:repository", RepositoryController, :show
  end
end
