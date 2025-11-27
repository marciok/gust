defmodule GustWeb.PageController do
  @moduledoc false
  use GustWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/dags")
  end
end
