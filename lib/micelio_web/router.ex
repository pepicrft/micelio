defmodule MicelioWeb.Router do
  use MicelioWeb, :router

  @api_rate_limit Application.compile_env(:micelio, :api_rate_limit, [])
  @api_rate_limit_limit Keyword.get(@api_rate_limit, :limit, 100)
  @api_rate_limit_window_ms Keyword.get(@api_rate_limit, :window_ms, 60_000)

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :fetch_live_flash
    plug :put_root_layout, html: {MicelioWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MicelioWeb.AuthenticationPlug
    plug MicelioWeb.Plugs.RateLimitPlug, limit: 200, window_ms: 60_000, bucket_prefix: "browser"
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug MicelioWeb.Plugs.ApiAuthenticationPlug

    plug MicelioWeb.Plugs.RateLimitPlug,
      limit: @api_rate_limit_limit,
      window_ms: @api_rate_limit_window_ms,
      bucket_prefix: "api",
      skip_if_authenticated: true
  end

  pipeline :api_docs do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: MicelioWeb.ApiSpec
  end

  pipeline :activity_pub do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug MicelioWeb.RequireAuthPlug
  end

  pipeline :require_admin do
    plug MicelioWeb.RequireAdminPlug
  end

  pipeline :load_resources do
    plug MicelioWeb.ResourcePlug, :load_account
    plug MicelioWeb.ResourcePlug, :load_repository
  end

  pipeline :og_image do
    plug :put_secure_browser_headers
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

  scope "/auth", MicelioWeb.Oauth do
    pipe_through :api

    post "/device", DeviceController, :create
  end

  scope "/api" do
    pipe_through :api_docs

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
    get "/docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  scope "/.well-known", MicelioWeb do
    pipe_through :activity_pub

    get "/webfinger", ActivityPubController, :webfinger
  end

  scope "/ap", MicelioWeb do
    pipe_through :activity_pub

    get "/actors/:handle", ActivityPubController, :actor
    get "/actors/:handle/outbox", ActivityPubController, :outbox
    post "/actors/:handle/inbox", ActivityPubController, :inbox
    get "/actors/:handle/followers", ActivityPubController, :followers
    get "/actors/:handle/following", ActivityPubController, :following
  end

  scope "/oauth", MicelioWeb.Oauth do
    pipe_through :api

    post "/register", RegistrationController, :register
  end

  scope "/device", MicelioWeb.Browser do
    pipe_through [:browser, :require_auth]

    get "/auth", DeviceAuthController, :new
    post "/auth/verify", DeviceAuthController, :verify
  end

  # Project routes (require authentication)
  scope "/projects", MicelioWeb do
    pipe_through [:browser, :require_auth]

    live_session :projects, on_mount: {MicelioWeb.LiveAuth, :require_auth} do
      live "/", ProjectLive.Index, :index
      live "/new", ProjectLive.New, :new
      live "/:organization_handle/:project_handle/edit", ProjectLive.Edit, :edit
      live "/:organization_handle/:project_handle", ProjectLive.Show, :show
      live "/:organization_handle/:project_handle/sessions", SessionLive.Index, :index
      live "/:organization_handle/:project_handle/sessions/:id", SessionLive.Show, :show
    end
  end

  # Organization routes (require authentication)
  scope "/organizations", MicelioWeb.Browser do
    pipe_through [:browser, :require_auth]

    get "/new", OrganizationController, :new
    post "/", OrganizationController, :create
  end

  # Admin routes (require admin access)
  scope "/admin", MicelioWeb.Browser do
    pipe_through [:browser, :require_auth, :require_admin]

    get "/", AdminController, :index
  end

  scope "/account", MicelioWeb.Browser do
    pipe_through [:browser, :require_auth]

    get "/", ProfileController, :show
    get "/devices", DeviceController, :index
    delete "/devices/:id", DeviceController, :delete
  end

  scope "/", MicelioWeb do
    pipe_through [:browser, :require_auth, :load_resources]

    live_session :repository_settings, on_mount: {MicelioWeb.LiveAuth, :require_auth} do
      live "/:account/:repository/settings", RepositoryLive.Settings, :edit
      live "/:account/:repository/settings/webhooks", RepositoryLive.Webhooks, :index
    end
  end

  scope "/", MicelioWeb.Browser do
    pipe_through [:browser, :require_auth, :load_resources]

    post "/:account/:repository/star", RepositoryController, :toggle_star
    post "/:account/:repository/fork", RepositoryController, :fork
  end

  scope "/og", MicelioWeb.Browser do
    pipe_through :og_image

    get "/:hash", OpenGraphImageController, :show
  end

  scope "/", MicelioWeb.Browser do
    pipe_through([:browser, :load_resources])

    get "/", PageController, :home

    get "/privacy", LegalController, :privacy
    get "/terms", LegalController, :terms
    get "/cookies", LegalController, :cookies
    get "/impressum", LegalController, :impressum
    get "/search", SearchController, :index

    get "/:account", AccountController, :show
    get "/:account/:repository/tree/*path", RepositoryController, :tree
    get "/:account/:repository/blob/*path", RepositoryController, :blob
    get "/:account/:repository/blame/*path", RepositoryController, :blame
    get "/:account/:repository", RepositoryController, :show
  end
end
