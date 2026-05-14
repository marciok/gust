defmodule GustWeb.API do
  @moduledoc """
  Router macro that mounts Gust API routes inside a host scope.

  Import this module into your Phoenix router and call `gust_api/0` inside an
  API scope. The host router owns the prefix, so the API can be mounted wherever
  the host application needs it:

      import GustWeb.API

      scope "/gust/api" do
        pipe_through [:api]

        gust_api()
      end
  """

  defmacro gust_api do
    quote do
      post("/dags/:dag_name/run", GustWeb.APIController, :create_run)
    end
  end
end
