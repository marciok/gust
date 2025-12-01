defmodule Gust.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc """
  The entry point for the Gust application.

  This module starts the supervision tree, which includes:
  * `Gust.Repo` - The database repository.
  * `Gust.Vault` - The vault for secrets.
  * `Gust.PubSub` - The PubSub system.
  * `Gust.Registry` - The process registry.
  * Dynamic supervisors for runners.
  * Workers for DAG loading, scheduling, and restarting (if enabled).
  """

  use Application

  @impl true
  def start(_type, _args) do
    env = System.get_env("MIX_ENV") || Mix.env() |> to_string()

    if env != "test" do
      folder = dag_folder()
      File.dir?(folder) || raise "DAG folder does not exist!: #{folder}"
    end

    base_children =
      [
        Gust.Vault,
        Gust.Repo,
        {Registry, keys: :unique, name: Gust.Registry},
        {DNSCluster, query: Application.get_env(:gust, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Gust.PubSub},
        {DynamicSupervisor, strategy: :one_for_one, name: dag_runner_supervisor()},
        {DynamicSupervisor, strategy: :one_for_one, name: dag_stage_runner_supervisor()},
        {DynamicSupervisor, strategy: :one_for_one, name: dag_task_runner_supervisor()}
      ]

    dag_children =
      if Application.get_env(:gust, :boot_dag) || System.get_env("PHX_SERVER") in ["true", "1"] do
        dag_scheduler_worker(env) ++
          dag_run_restater_worker(env) ++
          dag_loader_worker(env) ++
          dag_watcher(env)
      else
        []
      end

    children = base_children ++ dag_children
    Supervisor.start_link(children, strategy: :one_for_one, name: Gust.Supervisor)
  end

  defp dag_watcher(env) when env == "dev" do
    [{Gust.FileMonitor.Worker, %{dags_folder: dag_folder(), loader: dag_loader()}}]
  end

  defp dag_watcher(_env), do: []

  defp dag_folder, do: Application.get_env(:gust, :dags_folder)
  defp dag_runner_supervisor, do: Application.get_env(:gust, :dag_runner_supervisor)
  defp dag_task_runner_supervisor, do: Application.get_env(:gust, :dag_task_runner_supervisor)
  defp dag_stage_runner_supervisor, do: Application.get_env(:gust, :dag_stage_runner_supervisor)
  defp dag_loader, do: Application.get_env(:gust, :dag_loader)
  defp dag_scheduler, do: Application.get_env(:gust, :dag_scheduler)

  defp dag_loader_worker(env) when env == "test", do: []

  defp dag_loader_worker(_env) do
    [{Gust.DAG.Loader.Worker, %{dags_folder: dag_folder()}}]
  end

  defp dag_run_restater_worker(env) when env == "test", do: []

  defp dag_run_restater_worker(_env) do
    [Gust.DAG.RunRestarter.Worker]
  end

  defp dag_scheduler_worker(env) when env == "test", do: []

  defp dag_scheduler_worker(_env) do
    [Gust.DAG.Cron, {dag_scheduler(), name: dag_scheduler()}]
  end
end
