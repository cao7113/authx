defmodule AuthxWeb.PageController do
  use AuthxWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
