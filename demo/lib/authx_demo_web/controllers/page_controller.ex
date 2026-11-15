defmodule AuthxDemoWeb.PageController do
  use AuthxDemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home, current_user: conn.assigns[:current_user])
  end
end
