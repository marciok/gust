defmodule Gust.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc """
  The entry point for the Gust OTP application.

  This module defines the supervision tree responsible for loading DAGs, running
  tasks, scheduling recurring executions, and managing all runtime components of
  Gust. The application dynamically adjusts which workers are started depending on
  the environment (`dev`, `test`, or `prod`) and certain runtime flags.

  ## Environment-specific Behavior

  ### **Test environment**
  In the `test` environment, most of the DAG runtime system is **disabled** to keep
  tests fast, isolated, and deterministic. The following workers are **not** started:

  * `Gust.DAG.Loader.Worker` – prevents automatic DAG loading
  * `Gust.DAG.RunRestarter.Worker` – prevents auto-restoration of interrupted runs
  * `Gust.DAG.Cron` and the scheduler module – prevents background cron execution

  This means tests can use Gust's Repo, flows, and Ecto helpers without spawning
  schedulers or executing tasks unintentionally.

  ### **Dev environment**
  In the `dev` environment, Gust enables **live DAG reloading**. Whenever a file
  inside the configured `dags/` folder changes, Gust automatically reloads the DAG
  definition so the developer sees updates immediately without restarting the
  server.

  The following module is **dev-only**:

  * `Gust.FileMonitor.Worker` — watches the DAG directory and triggers reloads.

  ### **Prod environment**
  All DAG runtime workers are enabled:

  * The DAG loader
  * The DAG scheduler (cron)
  * The task, stage, and run supervisors
  * The run restarter (restart previously interrupted runs)
  * The registry, Repo, Vault, and PubSub infrastructure

  Production runs the full orchestration system as normal.

  ## Boot Logic and `PHX_SERVER`

  Gust normally starts its DAG runtime only when running the Phoenix server.
  This allows you to open an `iex -S mix` session without automatically starting:

  * the scheduler  
  * the DAG loader  
  * the DAG restarter  
  * the file watcher  

  To control this, Gust checks both:

  * `Application.get_env(:gust, :boot_dag)`
  * the `PHX_SERVER` environment variable

  If `PHX_SERVER` is set to `"true"` or `"1"`, Gust assumes you are running the
  web server (`mix phx.server` or a release with a web endpoint) and boots the
  entire DAG subsystem.  
  If not, Gust keeps DAG orchestration **disabled**, allowing safe console usage.

  This design prevents unwanted task execution when developers simply open an IEx
  session to inspect data or debug code.

  ## DAG Folder Validation

  Unless running in the test environment, Gust checks that the DAG folder exists
  on startup. If it does not, the application fails.

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
