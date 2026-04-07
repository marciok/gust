defmodule GustWeb.WellKnownController do
  @moduledoc false
  use GustWeb, :controller

  def not_found(conn, _params) do
    send_resp(conn, :not_found, "Not Found")
  end
end
