case :os.type() do
  {:unix, :linux} ->
    nil

  _ ->
    ExUnit.configure(exclude: [linux_only: true])
end

# Add support directory to code path for test fixtures and helpers
Code.compile_file("support/shell_fixtures.ex", __DIR__)

# Start applications needed for testing
Application.ensure_all_started(:erlexec)
Application.ensure_all_started(:mox)

# Configure the gust app to use the mock DAG logger
Application.put_env(:gust, :dag_logger, Gust.DAGLoggerMock)

ExUnit.start()
