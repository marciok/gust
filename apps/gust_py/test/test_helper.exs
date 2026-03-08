Application.ensure_all_started(:mox)

Mox.defmock(GustPy.ExecutorMock, for: GustPy.Executor)
Mox.defmock(GustPy.TaskMessengerMock, for: GustPy.TaskMessenger)
Mox.defmock(GustPy.DAGLoggerMock, for: Gust.DAG.Logger)

Application.put_env(:gust_py, :executor, GustPy.ExecutorMock)
Application.put_env(:gust_py, :task_messenger, GustPy.TaskMessengerMock)
Application.put_env(:gust, :dag_logger, GustPy.DAGLoggerMock)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Gust.Repo, :manual)
