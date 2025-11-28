defmodule DobbyWeb.Router do
  use DobbyWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DobbyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # 管理员认证管道
  pipeline :require_authenticated_admin do
    plug DobbyWeb.Plugs.RequireAuthenticatedAdmin
  end

  # 公共访问（前台用户）
  scope "/", DobbyWeb.Public do
    pipe_through :browser

    # 刮奖入口（通过交易码 + 活动 UUID）
    live "/campaigns/:campaign_id/scratch/:transaction_number", ScratchLive, :show
    # 信息提交页
    live "/submit/:winning_record_id", SubmitLive, :show
  end

  # 公共访问（前台用户）- 保留首页
  scope "/", DobbyWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # 管理员后台
  scope "/admin", DobbyWeb.Admin do
    pipe_through :browser

    # 登录/登出（无需认证）
    live_session :admin_auth do
      live "/login", SessionLive, :new
    end

    # 登录处理（使用 Controller）
    post "/session", SessionController, :create
    delete "/session", SessionController, :delete

    # 需要认证的管理后台
    live_session :admin, on_mount: DobbyWeb.AdminAuthLive do
      pipe_through :require_authenticated_admin

      live "/", DashboardLive, :index
      live "/campaigns", CampaignLive.Index, :index
      live "/campaigns/new", CampaignLive.Index, :new
      live "/campaigns/:id/edit", CampaignLive.Index, :edit
      live "/campaigns/:id/preview", CampaignLive.Index, :preview
      live "/prize-library", PrizeLibraryLive.Index, :index
      live "/prize-library/new", PrizeLibraryLive.Index, :new
      live "/prize-library/:id/edit", PrizeLibraryLive.Index, :edit
      live "/campaigns/:campaign_id/prizes", PrizeLive.Index, :index
      live "/campaigns/:campaign_id/prizes/new", PrizeLive.Index, :new
      live "/campaigns/:campaign_id/prizes/:id/edit", PrizeLive.Index, :edit
      live "/campaigns/:campaign_id/prizes/import", PrizeLive.Index, :import
      live "/email-templates", EmailTemplateLive.Index, :index
      live "/email-templates/new", EmailTemplateLive.Index, :new
      live "/email-templates/:id/edit", EmailTemplateLive.Index, :edit
      live "/email-logs", EmailLogLive.Index, :index
      live "/campaigns/:id/winning-records", WinningRecordLive.Index, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", DobbyWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:dobby, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DobbyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
