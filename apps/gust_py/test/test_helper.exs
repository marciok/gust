Application.ensure_all_started(:mox)

Mox.defmock(GustPy.ExecutorMock, for: GustPy.Executor)

ExUnit.start()
