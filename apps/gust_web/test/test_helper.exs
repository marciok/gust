Application.ensure_all_started(:mox)

Mox.defmock(GustWeb.DAGLoaderMock, for: Gust.DAG.Loader)
Mox.defmock(GustWeb.DAGParserMock, for: Gust.DAG.Parser)
Mox.defmock(GustWeb.DAGRunnerSupervisorMock, for: Gust.DAG.RunnerSupervisor)
Mox.defmock(GustWeb.DAGTerminatorMock, for: Gust.DAG.Terminator)
Mox.defmock(GustWeb.DAGRunTriggerMock, for: Gust.DAG.Run.Trigger)
Mox.defmock(GustWeb.MCPToolsMock, for: GustWeb.MCP.Tools)
Mox.defmock(GustWeb.MCPResourcesMock, for: GustWeb.MCP.Resources)

Application.put_env(:gust, :dag_parser, GustWeb.DAGParserMock)
Application.put_env(:gust, :dag_runner_supervisor, GustWeb.DAGRunnerSupervisorMock)
Application.put_env(:gust, :dag_loader, GustWeb.DAGLoaderMock)
Application.put_env(:gust, :dag_run_trigger, GustWeb.DAGRunTriggerMock)
Application.put_env(:gust, :dag_terminator, GustWeb.DAGTerminatorMock)
Application.put_env(:gust_web, :mcp_tools, GustWeb.MCPToolsMock)
Application.put_env(:gust_web, :mcp_resources, GustWeb.MCPResourcesMock)
Application.put_env(:gust_web, :display_date_format,
  long: "%H:%M:%S %Y-%m-%d",
  short: "%H:%M:%S %m/%d"
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Gust.Repo, :manual)
