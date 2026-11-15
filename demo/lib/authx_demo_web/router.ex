defmodule AuthxDemoWeb.Router do
  use AuthxDemoWeb, :router
  use AshAuthentication.Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AuthxDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AuthxDemoWeb do
    pipe_through :browser

    get "/", PageController, :home
    auth_routes(AuthController, AuthxDemo.Accounts.User, path: "/auth")
    post "/sign-out", AuthController, :sign_out
  end

  # Other scopes may use custom stacks.
  # scope "/api", AuthxDemoWeb do
  #   pipe_through :api
  # end
end
