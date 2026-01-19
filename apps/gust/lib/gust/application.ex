defmodule Gust.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc """
  Starts the Gust OTP application and wires the supervision tree.

  Gust orchestrates DAG execution, scheduling, and runtime infrastructure. This
  module builds the child list based on the environment and runtime flags so the
  right workers are started (or skipped) for the current mode.

  ## Environment behavior

  ### Test
  In `test`, DAG runtime workers are disabled to keep test runs fast and
  deterministic. The DAG loader, cron scheduler, and run restarter are not
  started, so tests can use Repo and Ecto helpers without background execution.

  ### Dev
  In `dev`, Gust enables live DAG reloading. The file monitor watches the
  configured `dags/` directory and triggers reloads on changes.

  ### Prod
  In `prod`, the full runtime is enabled: DAG loading, cron scheduling, run
  restarts, supervisors, and core infrastructure such as Registry, Repo, Vault,
  and PubSub.

  ## Boot control (`PHX_SERVER`)

  Gust only boots the DAG runtime when the Phoenix server is running. This keeps
  `iex -S mix` sessions safe and quiet by default.

  The decision is based on:

  * `Application.get_env(:gust, :boot_dag)`
  * the `PHX_SERVER` environment variable

  If `PHX_SERVER` is `"true"` or `"1"`, Gust assumes a web server is running and
  starts the full DAG subsystem. Otherwise, DAG orchestration stays disabled.

  ## DAG folder validation

  Outside of `test`, Gust validates that the configured DAG folder exists at
  startup. If it is missing, the application fails fast.
  """

  use Application

  @impl true
  def start(_type, _args) do
    env = System.get_env("MIX_ENV") || Mix.env() |> to_string()
    folder = Application.get_env(:gust, :dags_folder)

    if env != "test" do
      File.dir?(folder) || raise "DAG folder does not exist!: #{folder}"
    end

    base_children =
      [
        Gust.Vault,
        Gust.Repo,
        {Registry, keys: :unique, name: Gust.Registry},
        {DNSCluster, query: Application.get_env(:gust, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Gust.PubSub}
      ]

    role = System.get_env("GUST_ROLE", "single")

    children = base_children ++ Gust.AppChildren.for_role(role, env, folder)
    Supervisor.start_link(children, strategy: :one_for_one, name: Gust.Supervisor)
  end
end
