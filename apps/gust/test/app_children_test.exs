defmodule AppChildrenTest do
  alias Gust.AppChildren
  use Gust.DataCase

  import Gust.ApplicationEnvHelpers

  setup :init_dag_source

  defp loader, do: Application.get_env(:gust, :dag_loader)

  defp runners do
    [
      {DynamicSupervisor,
       strategy: :one_for_one, name: Application.get_env(:gust, :dag_runner_supervisor)},
      {DynamicSupervisor,
       strategy: :one_for_one, name: Application.get_env(:gust, :dag_task_runner_supervisor)}
    ]
  end

  defp leader do
    [
      Gust.Leader,
      {DynamicSupervisor, [strategy: :one_for_one, name: Gust.LeaderOnlySupervisor]}
    ]
  end

  describe "for_role/2" do
    setup do
      Application.delete_env(:gust, :dag_sources)
      :ok
    end

    test "returns children for core and single roles in dev" do
      children =
        [
          Gust.Run.DispatcherSupervisor,
          Gust.DAG.Loader.Worker,
          {Gust.FileMonitor.Worker, %{id: "default-folder", loader: loader()}}
        ] ++ leader() ++ runners()

      assert children == AppChildren.for_role("core", "dev")
      assert children == AppChildren.for_role("single", "dev")
    end

    test "starts the run dispatcher supervisor only for execution roles" do
      replace_env(:run_dispatcher, Gust.PGNotifier.Worker)

      assert [Gust.Run.DispatcherSupervisor | _children] = AppChildren.for_role("core", "dev")
      refute Gust.Run.DispatcherSupervisor in AppChildren.for_role("web", "dev")
      refute Gust.Run.DispatcherSupervisor in AppChildren.for_role("console", "dev")
    end

    test "web and console roles start loader and monitors in dev" do
      expected = [
        Gust.DAG.Loader.Worker,
        {Gust.FileMonitor.Worker, %{id: "default-folder", loader: loader()}}
      ]

      assert expected == AppChildren.for_role("web", "dev")
      assert expected == AppChildren.for_role("console", "dev")
    end

    test "returns children for non-web roles in test" do
      assert runners() == AppChildren.for_role("core", "test")
      assert runners() == AppChildren.for_role("single", "test")
      assert [] == AppChildren.for_role("console", "test")
      assert [] == AppChildren.for_role("web", "test")
    end

    test "prod skips only the Folder OS watcher" do
      children =
        [Gust.Run.DispatcherSupervisor, Gust.DAG.Loader.Worker] ++ leader() ++ runners()

      assert children == AppChildren.for_role("core", "prod")
      assert children == AppChildren.for_role("single", "prod")
      assert [Gust.DAG.Loader.Worker] == AppChildren.for_role("web", "prod")
      assert [Gust.DAG.Loader.Worker] == AppChildren.for_role("console", "prod")
    end

    test "prod starts monitors for polling sources, visible to web and console" do
      Application.put_env(:gust, :dag_sources, [
        {"folder-1", type: Gust.DAG.Source.Folder, folder: "/tmp/x"},
        {"git-1", type: Gust.DAG.Source.Git, url: "https://example.com/repo.git"},
        {"s3-1", type: Gust.DAG.Source.S3, bucket: "b"}
      ])

      watchers = [
        {Gust.FileMonitor.Worker, %{id: "git-1", loader: loader()}},
        {Gust.FileMonitor.Worker, %{id: "s3-1", loader: loader()}}
      ]

      assert [Gust.DAG.Loader.Worker | watchers] == AppChildren.for_role("web", "prod")
      assert [Gust.DAG.Loader.Worker | watchers] == AppChildren.for_role("console", "prod")
      assert watchers -- AppChildren.for_role("core", "prod") == []
    end
  end
end
