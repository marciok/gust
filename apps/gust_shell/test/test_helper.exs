ExUnit.start()

# Set up Mox for mocking
Mox.defmock(Gust.DAGLoggerMock, for: Gust.DAG.Logger)

# Configure the gust app to use the mock DAG logger
Application.put_env(:gust, :dag_logger, Gust.DAGLoggerMock)
