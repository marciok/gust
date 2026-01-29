defmodule Mix.Tasks.GustWeb.Install do
  use Igniter.Mix.Task

  alias Igniter.Code.Module
  alias Igniter.Project.Config
  alias Igniter.Project.Deps

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    name = igniter |> Igniter.Project.Application.app_name

    igniter = ( igniter
      |> Deps.add_dep({:file_system, "~> 1.1", only: :dev})
      |> Deps.add_dep({:hackney, "~> 1.9"})
      |> Deps.add_dep({:plug_cowboy, "~> 2.7", only: :prod})
    )

    File.mkdir_p!("dags")
    # %w(dags config) |> Enum.each(&File.mkdir_p!/1)

    igniter = ( igniter
    |> Config.configure("config.exs", name, [:gust], {:code, quote do [ app_name: unquote(name), dag_logger: Gust.DAG.Logger.Database ] end})
    |> Config.configure("config.exs", name, [name], [ ecto_repos: [Gust.Repo] ])
    |> Config.configure("config.exs", name, [:logger], {:code, [
      backends: [ console: Gust.DAG.Logger.Database ],
      default_formatter: [
        format: "\$time \$metadata[\$level] \$message\n",
        metadata: [:request_id, :task_id, :attempt],
      ],
    ]}) )

    File.write(".gitignore", """
    /_build/        # The directory Mix will write compiled artifacts to.
    /cover/         # If you run "mix test --cover", coverage assets end up here.
    /deps/          # The directory Mix downloads your dependencies sources to.
    /doc/           # Where third-party dependencies like ExDoc output generated docs.
    /.fetch         # Ignore .fetch files in case you like to edit your project deps locally.
    erl_crash.dump  # If the VM crashes, it generates a dump, let's ignore it too.
    *.ez            # Also ignore archive artifacts (built via "mix archive.build").
    #{name}-*.tar   # Ignore package tarball (built via "mix hex.build").
    /tmp/           # Temporary files, for example, from tests.
    """, [:append])

    random = fn n -> :crypto.strong_rand_bytes(n) |> Base.encode64(padding: false) end
    rand   = fn n -> random.(n) |> binary_part(0, n) end

    IO.puts "==> Gust Dev Config"
    igniter = ( igniter
    |> Config.configure_group("dev.exs", name, [ :gust_web, GustWeb.Endpoint ], [
        url: { :host, "localhost" },
        adapter: Bandit.PhoenixAdapter,
        render_errors: [ layout: false,
          formats: [html: GustWeb.ErrorHTML, json: GustWeb.ErrorJSON], ],
        pubsub_server: Gust.PubSub,
        live_view: [ signing_salt: rand.(8) ],
        http: [
          ip: {127, 0, 0, 1},
          port: Sourceror.parse_string!(~s[String.to_integer(System.get_env("PORT") || "4000")])
        ],
        check_origin: false,
        secret_key_base: rand.(8),
      ]
    ) )

    # IO.puts("==> Adding dev config file")

    File.write(".env", """
      SIGNING_SALT=#{rand.(8)}
      PROD_SIGNING_SALT=#{rand.(8)}
      SECRET_KEY_BASE=#{rand.(64)}
      B64_SECRETS_CLOAK_KEY=#{random.(64)}
    """, [:append])

    # cat > config/runtime.exs << EOF
    # if config_env() == :prod do
    #   config :gust, b64_secrets_cloak_key: System.get_env("B64_SECRETS_CLOAK_KEY")

    #   database_url =
    #     System.get_env("DATABASE_URL") ||
    #       raise """
    #       environment variable DATABASE_URL is missing.
    #       For example: ecto://USER:PASS@HOST/DATABASE
    #       """

    #   maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

    #   config :gust, Gust.Repo,
    #     url: database_url,
    #     pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    #     socket_options: maybe_ipv6

    #   secret_key_base =
    #     System.get_env("SECRET_KEY_BASE") ||
    #       raise """
    #       environment variable SECRET_KEY_BASE is missing.
    #       You can generate one by calling: mix phx.gen.secret
    #       """

    #   host = System.get_env("PHX_HOST") || "example.com"
    #   port = String.to_integer(System.get_env("PORT") || "4000")

    #   config :gust_web, GustWeb.Endpoint,
    #     server: true,
    #     url: [host: host, port: 443, scheme: "https"],
    #     http: [
    #       ip: {0, 0, 0, 0, 0, 0, 0, 0},
    #       port: port
    #     ],
    #     secret_key_base: secret_key_base

    #   config :gust, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
    # end
    # EOF

    # cat > config/prod.exs << EOF
    # import Config

    # config :gust_web, GustWeb.Endpoint,
    #   cache_static_manifest: "priv/static/cache_manifest.json",
    #   secret_key_base: System.get_env("SECRET_KEY_BASE") || raise("environment variable SECRET_KEY_BASE is missing."),
    #   check_origin: true,
    #   live_view: [signing_salt: "#{PROD_SIGNING_SALT}"]

    # # Configures Swoosh API Client
    # config :swoosh, :api_client, Swoosh.ApiClient.Req

    # # Disable Swoosh Local Memory Storage
    # config :swoosh, local: false

    # # Do not print debug messages in production
    # config :logger, level: :info

    # config :gust_web, basic_auth: true

    # config :gust, dags_folder: Path.join(File.cwd!(), "dags")

    # config :gust, dag_runner_supervisor: Gust.DAG.RunnerSupervisor.DynamicSupervisor
    # config :gust, dag_task_runner_supervisor: Gust.DAG.TaskRunnerSupervisor.DynamicSupervisor
    # config :gust, dag_stage_runner_supervisor: Gust.DAG.StageRunnerSupervisor.DynamicSupervisor
    # config :gust, dag_scheduler: Gust.DAG.Scheduler.Worker
    # config :gust, dag_loader: Gust.DAG.Loader.Worker
    # config :gust, dag_stage_runner: Gust.DAG.Runner.StageWorker
    # EOF

    # IO.puts "==> Creating sample DAG in dags/hello_world.ex"

    # cat > dags/hello_world.ex << EOF
    # defmodule HelloWorld do
    #   # Schedule is optional, if you change, make sure to restart the server 
    #   # in order to update the cron job.
    #   use Gust.DSL, schedule: "* * * * *"
    #   require Logger

    #   task :first_task, downstream: [:second_task], store_result: true do
    #     greetings = "Hi from first_task"
    #     Logger.info(greetings)
    #     # The return value must be a map when store result is true
    #     %{result: greetings}
    #   end

    #   task :second_task, ctx: %{run_id: run_id} do
    #     task = Gust.Flows.get_task_by_name_run("first_task", run_id)
    #     Logger.info(task.result)
    #   end
    # end
    # EOF

    # IO.puts "==> Downloading gust static assets"
    # curl -L https://github.com/marciok/gust/releases/download/v#{GustWeb.MixProject.project[:version]}/gust_static_assets.tar.gz -o gust_static_assets.tar.gz

    # IO.puts "==> Extracting gust static assets"
    # mkdir -p priv/static
    # tar -xzf gust_static_assets.tar.gz -C priv/static/ --strip-components=1

    # IO.puts """
    # Gust assets installed at priv/static/assets/gust

    # ==> Done!
    # Your Gust app '$name' is ready.
    # Now, you need to:
    # 1) Configure Postgres credentials on dev.exs
    # 2) Create & migrate database:
    # mix ecto.create --repo Gust.Repo && mix ecto.migrate --repo Gust.Repo
    # 3) Run Gust start command:
    # mix gust.start
    # """
    igniter
  end
end
