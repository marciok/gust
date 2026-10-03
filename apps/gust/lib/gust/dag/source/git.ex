defmodule Gust.DAG.Source.Git do
  @compile {:no_warn_undefined,
            [
              {:git, :clone, 3},
              {:git, :open, 1},
              {:git, :pull, 2},
              {:git, :log, 2},
              {:git, :symbolic_ref, 2},
              {:git, :checkout, 2}
            ]}

  @moduledoc """
  DAG source that loads definitions from a Git repository.

  Requires the egit library (~> 0.3) to be installed. Clones or pulls the
  repository to a local directory, then parses DAG files from the checked-out tree.
  Changes are detected via polling.

  Configuration:
    - `:url`          — Git repository URL (required)
    - `:branch`       — Branch to check out (default: "main")
    - `:path`         — Local path where to clone/pull (default: System.tmp_dir)
    - `:poll_seconds` — Polling interval in seconds (default: 30)
    - `:credentials`  — Authentication credentials (optional, see below)

  Credentials can be provided as:

  ### SSH Key Authentication
  ```elixir
  credentials: [
    type: :ssh_key,
    username: "git",
    privkey_path: "/home/user/.ssh/id_rsa",  # or privkey: <<"...PEM content...">>
    pubkey_path: "/home/user/.ssh/id_rsa.pub",  # or pubkey: <<"...PEM content...">>
    passphrase: ""
  ]
  ```

  ### Username/Password Authentication
  ```elixir
  credentials: [
    type: :userpass,
    username: "user",
    password: "secret"  # or use environment variables
  ]
  ```

  ### Personal Access Token
  ```elixir
  credentials: [
    type: :token,
    username: "user",
    token: "github_token"
  ]
  ```

  ### SSH Agent (uses system SSH agent)
  ```elixir
  credentials: [
    type: :ssh_agent,
    username: "git"
  ]
  ```

  Environment variables can be used for sensitive values:
  - `GIT_CREDENTIALS_USERNAME` - Username
  - `GIT_CREDENTIALS_PASSWORD` - Password or token
  - `GIT_CREDENTIALS_PASSPHRASE` - SSH key passphrase
  """

  @behaviour Gust.DAG.Source

  require Logger
  alias Gust.DAG.Adapter
  alias Gust.DAG.Folder
  alias Gust.DAG.Parser
  alias Gust.DAG.Source.Polling

  @impl true
  def load(effective_time \\ nil) do
    with {:ok, repo_path} <- ensure_egit_available(),
         {:ok, repo_path} <- ensure_repo_cloned(repo_path) do
      dags =
        case effective_time do
          %DateTime{} ->
            load_from_historical_commit(repo_path, effective_time)

          nil ->
            load_from_path(repo_path)
        end

      # Partition DAGs into success and error lists, unwrapping the tuples
      {success, error} =
        Enum.reduce(dags, {[], []}, fn
          {name, {:ok, value}}, {success, error} -> {[{name, value} | success], error}
          {name, {:error, reason}}, {success, error} -> {success, [{name, reason} | error]}
        end)

      %{success: success |> Enum.reverse(), error: error |> Enum.reverse()}
    else
      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    e ->
      {:error, inspect(e)}
  end

  @impl true
  def monitor(loader_pid, _config \\ %{}) do
    poll_interval_ms = poll_seconds() * 1_000

    Polling.start_link(loader_pid, &load/0, poll_interval_ms)
  end

  @impl true
  def name, do: "Git"

  defp ensure_egit_available do
    if Code.ensure_loaded?(:git) do
      {:ok, get_repo_path()}
    else
      {:error,
       "egit library not available. Add {:egit, \"~> 0.3\"} to your dependencies and run 'mix deps.get'"}
    end
  end

  defp load_from_path(repo_path) do
    Adapter.parser_modules()
    |> Enum.flat_map(&load_extension(&1, repo_path))
    |> Enum.into(%{})
  end

  defp load_from_historical_commit(repo_path, effective_time) do
    with {:ok, repo} <- :git.open(to_charlist(repo_path)),
         # Format the time for git log filtering
         # Convert DateTime to ISO 8601 string that git understands
         time_str = DateTime.to_iso8601(effective_time),
         # Find the last commit before or at effective_time
         # Using git log with --until flag to get commits before effective_time
         {:ok, [commit | _]} <- :git.log(repo, until: time_str, max_count: 1) do
      # Checkout this specific commit (detached HEAD state)
      current_branch = get_current_branch(repo)
      :git.checkout(repo, commit)

      # Load DAGs from this historical state
      dags = load_from_path(repo_path)

      # Return to the original branch
      current_branch && :git.checkout(repo, current_branch)

      dags
    else
      {:ok, []} ->
        # No commits found before effective_time
        {:ok, []}

      {:error, reason} ->
        {:error, "Failed to find historical commit: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Failed to load DAGs from git: #{inspect(e)}"}
  end

  defp get_current_branch(repo) do
    case :git.symbolic_ref(repo, "HEAD") do
      {:ok, ref} -> ref
      {:error, _} -> nil
    end
  rescue
    _e -> nil
  end

  defp load_extension(parser_module, repo_path) do
    parser_module.extensions()
    |> Enum.map(&Folder.list_files(repo_path, &1))
    |> Enum.concat()
    |> Enum.map(fn filename ->
      path = Folder.absolute_path(repo_path, filename)
      dag_name = Folder.dag_name(path)
      result = Parser.parse(parser_module, path)
      {dag_name, result}
    end)
  end

  defp ensure_repo_cloned(repo_path) do
    case get_url() do
      url when is_binary(url) ->
        branch = get_branch()
        dir_exists = File.dir?(Path.join(repo_path, ".git"))

        pull_or_clone_repo(repo_path, url, branch, dir_exists)

      _ ->
        {:error, "Git DAG source requires :url in the dag_source tuple config"}
    end
  rescue
    e in ErlangError ->
      {:error, "Failed ensure git repository '#{repo_path}' cloned: #{inspect(e.original)}"}
  end

  defp pull_or_clone_repo(repo_path, _url, branch, true), do: pull_repo(repo_path, branch)
  defp pull_or_clone_repo(repo_path, url, branch, false), do: clone_repo(url, repo_path, branch)

  defp clone_repo(url, path, branch) do
    Logger.info("Cloning git repository: #{url} (branch: #{branch}) to #{path}")

    # Ensure parent directory exists
    File.mkdir_p!(Path.dirname(path))

    case build_credentials() do
      {:ok, opts} ->
        :git.clone(url, path, opts)
        {:ok, path}

      {:error, reason} ->
        {:error, "Failed to build git options: #{inspect(reason)}"}
    end
  end

  defp pull_repo(repo_path, _branch) do
    Logger.info("Pulling git repository: #{repo_path}")

    repo = :git.open(repo_path)

    case build_credentials() do
      {:ok, opts} ->
        with :ok <- :git.pull(repo, opts), do: {:ok, repo_path}

      {:error, reason} ->
        {:error, "Failed to build git options for pull: #{inspect(reason)}"}
    end
  rescue
    e in ErlangError ->
      {:error, "Failed to open git repository '#{repo_path}': #{inspect(e.original)}"}
  end

  defp build_credentials do
    config = Gust.DAG.Source.config()
    creds_config = Keyword.get(config, :credentials)

    case creds_config do
      nil ->
        {:ok, %{}}

      [] ->
        {:ok, %{}}

      creds when is_list(creds) ->
        creds_type = Keyword.get(creds, :type)
        build_credentials_by_type(creds_type, creds)

      creds when is_map(creds) ->
        {:ok, %{credentials: creds}}
    end
  end

  defp build_credentials_by_type(:ssh_key, creds) do
    username = Keyword.get(creds, :username, "git")
    passphrase = get_env_or_config(creds, :passphrase, "GIT_CREDENTIALS_PASSPHRASE", "")

    with {:ok, privkey} <- read_ssh_key(creds, :privkey, :privkey_path),
         {:ok, pubkey} <- read_ssh_key(creds, :pubkey, :pubkey_path) do
      {:ok,
       %{
         type: :ssh_key,
         username: to_string(username),
         privkey: privkey,
         pubkey: pubkey,
         passphrase: to_string(passphrase)
       }}
    end
  end

  defp build_credentials_by_type(:userpass, creds) do
    username = get_env_or_config(creds, :username, "GIT_CREDENTIALS_USERNAME")
    password = get_env_or_config(creds, :password, "GIT_CREDENTIALS_PASSWORD")

    {:ok,
     %{
       type: :userpass,
       username: to_string(username),
       password: to_string(password)
     }}
  end

  defp build_credentials_by_type(:token, creds) do
    username = get_env_or_config(creds, :username, "GIT_CREDENTIALS_USERNAME")
    token = get_env_or_config(creds, :token, "GIT_CREDENTIALS_PASSWORD")

    {:ok,
     %{
       type: :token,
       username: to_string(username),
       token: to_string(token)
     }}
  end

  defp build_credentials_by_type(:ssh_agent, creds) do
    username = Keyword.get(creds, :username, "git")

    {:ok,
     %{
       type: :ssh_agent,
       username: to_string(username)
     }}
  end

  defp build_credentials_by_type(type, _creds) when type != nil do
    {:error, "Unknown credentials type: #{inspect(type)}"}
  end

  defp build_credentials_by_type(nil, _creds) do
    {:error, "No credentials provided"}
  end

  defp read_ssh_key(creds, key_atom, path_atom) do
    case {Keyword.get(creds, key_atom), Keyword.get(creds, path_atom)} do
      {content, _} when is_binary(content) ->
        {:ok, content}

      {_, path} when is_binary(path) ->
        case File.read(path) do
          {:ok, content} -> {:ok, content}
          {:error, _reason} -> {:error, "Failed to read SSH key from #{path}"}
        end

      _ ->
        {:error, "No SSH #{key_atom} specified"}
    end
  end

  defp get_env_or_config(creds, config_key, env_var, default \\ nil),
    do: System.get_env(env_var) || Keyword.get(creds, config_key) || default

  defp get_url,
    do: Keyword.get(config(), :url)

  defp get_branch, do: Keyword.get(config(), :branch, "main")

  defp get_repo_path,
    do: Keyword.get(config(), :path, Path.join(System.tmp_dir!(), "gust-dags-repo"))

  defp poll_seconds, do: Keyword.get(config(), :poll_seconds, 30)

  defp config, do: Gust.DAG.Source.config()
end
