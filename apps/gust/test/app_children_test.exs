defmodule AppChildrenTest do
  alias Gust.AppChildren
  use Gust.DataCase

  @dags_folder "folder/path/dags"

  describe "for_core/3" do
    setup do
      children = [
        Gust.Run.Pooler,
        {Gust.DAG.Loader.Worker, %{dags_folder: @dags_folder}},
        {Gust.FileMonitor.Worker,
         %{dags_folder: @dags_folder, loader: Application.get_env(:gust, :dag_loader)}},
        Gust.Leader,
        {DynamicSupervisor, [strategy: :one_for_one, name: Gust.LeaderOnlySupervisor]},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Application.get_env(:gust, :dag_runner_supervisor)},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Application.get_env(:gust, :dag_stage_runner_supervisor)},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Application.get_env(:gust, :dag_task_runner_supervisor)}
      ]

      %{base_children: children}
    end

    test "list children for role when mix env is dev", %{
      base_children: children
    } do
      mix_env = "dev"

      assert children == AppChildren.for_role("core", mix_env, @dags_folder)
      assert children == AppChildren.for_role("single", mix_env, @dags_folder)

      assert [{Gust.DAG.Loader.Worker, %{dags_folder: @dags_folder}}] =
               AppChildren.for_role("web", "dev", @dags_folder)
    end

    test "list children for role when mix env is test" do
      mix_env = "test"

      children = [
        {DynamicSupervisor,
         strategy: :one_for_one, name: Application.get_env(:gust, :dag_runner_supervisor)},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Application.get_env(:gust, :dag_stage_runner_supervisor)},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Application.get_env(:gust, :dag_task_runner_supervisor)}
      ]

      assert children == AppChildren.for_role("core", mix_env, @dags_folder)
      assert children == AppChildren.for_role("single", mix_env, @dags_folder)
      assert [] = AppChildren.for_role("web", mix_env, @dags_folder)
    end

    test "list children for role when mix env is prod" do
      mix_env = "prod"

      children = [
        Gust.Run.Pooler,
        {Gust.DAG.Loader.Worker, %{dags_folder: @dags_folder}},
        Gust.Leader,
        {DynamicSupervisor, [strategy: :one_for_one, name: Gust.LeaderOnlySupervisor]},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Application.get_env(:gust, :dag_runner_supervisor)},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Application.get_env(:gust, :dag_stage_runner_supervisor)},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Application.get_env(:gust, :dag_task_runner_supervisor)}
      ]

      assert children == AppChildren.for_role("core", mix_env, @dags_folder)
      assert children == AppChildren.for_role("single", mix_env, @dags_folder)

      assert [{Gust.DAG.Loader.Worker, %{dags_folder: @dags_folder}}] =
               AppChildren.for_role("web", mix_env, @dags_folder)
    end
  end
end
