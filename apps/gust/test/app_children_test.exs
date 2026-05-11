defmodule AppChildrenTest do
  alias Gust.AppChildren
  use Gust.DataCase

  @dags_folder "folder/path/dags"

  describe "for_role/3" do
    setup do
      children = [
        Gust.Run.Pooler,
        Gust.DAG.Terminator.Worker,
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

    test "returns children for core and single roles in dev", %{
      base_children: children
    } do
      mix_env = "dev"

      assert children == AppChildren.for_role("core", mix_env, @dags_folder)
      assert children == AppChildren.for_role("single", mix_env, @dags_folder)

      assert [{Gust.DAG.Loader.Worker, %{dags_folder: @dags_folder}}] =
               AppChildren.for_role("web", "dev", @dags_folder)
    end

    test "skips pooler and terminator for console role outside test" do
      dev_children = [
        {Gust.DAG.Loader.Worker, %{dags_folder: @dags_folder}}
      ]

      prod_children = [
        {Gust.DAG.Loader.Worker, %{dags_folder: @dags_folder}}
      ]

      assert dev_children == AppChildren.for_role("console", "dev", @dags_folder)
      assert prod_children == AppChildren.for_role("console", "prod", @dags_folder)
    end

    test "returns children for non-web roles in test" do
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
      assert [] == AppChildren.for_role("console", mix_env, @dags_folder)
      assert [] = AppChildren.for_role("web", mix_env, @dags_folder)
    end

    test "returns children for core and single roles in prod" do
      mix_env = "prod"

      children = [
        Gust.Run.Pooler,
        Gust.DAG.Terminator.Worker,
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
