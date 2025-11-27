Application.ensure_all_started(:mox)

Mox.defmock(GustWeb.DAGLoaderMock, for: Gust.DAG.Loader)
Mox.defmock(GustWeb.DAGParserMock, for: Gust.DAG.Parser)
Mox.defmock(GustWeb.DAGRunnerSupervisorMock, for: Gust.DAG.RunnerSupervisor)
Mox.defmock(GustWeb.DAGTerminatorMock, for: Gust.DAG.Terminator)
Mox.defmock(GustWeb.DAGRunRestarterMock, for: Gust.DAG.RunRestarter)

Application.put_env(:gust, :dag_parser, GustWeb.DAGParserMock)
Application.put_env(:gust, :dag_runner_supervisor, GustWeb.DAGRunnerSupervisorMock)
Application.put_env(:gust, :dag_loader, GustWeb.DAGLoaderMock)
Application.put_env(:gust, :dag_run_restarter, GustWeb.DAGRunRestarterMock)
Application.put_env(:gust, :dag_terminator, GustWeb.DAGTerminatorMock)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Gust.Repo, :manual)
