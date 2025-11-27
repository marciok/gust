defmodule Gust.Repo do
  use Ecto.Repo,
    otp_app: :gust,
    adapter: Ecto.Adapters.Postgres
end
