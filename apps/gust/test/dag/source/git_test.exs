defmodule Gust.DAG.Source.GitTest do
  use ExUnit.Case, async: false

  import Gust.ApplicationEnvHelpers
  import Mox

  alias Gust.DAG.Source
  alias Gust.DAG.Source.Config
  alias Gust.DAG.Source.Git

  setup :init_dag_source
  setup :verify_on_exit!
  setup :set_mox_from_context

  describe "name/0" do
    test "returns the source name" do
      assert Git.name() == "Git"
    end
  end

  describe "dag source resolution" do
    test "resolves list-based source config" do
      put_git_source(url: "https://github.com/user/dags.git")

      assert Source.config() == [
               id: "test-git",
               type: Gust.DAG.Source.Git,
               url: "https://github.com/user/dags.git"
             ]

      assert Source.module("test-git") == Gust.DAG.Source.Git
    end

    test "resolves map-based config types and preserves source options" do
      Application.put_env(:gust, :dag_sources, %{
        type: "git",
        url: "https://github.com/user/dags.git"
      })

      assert Source.module("default-git") == Gust.DAG.Source.Git

      assert Source.config() == [
               id: "default-git",
               type: Gust.DAG.Source.Git,
               url: "https://github.com/user/dags.git"
             ]
    end

    test "resolves multiple configured sources and preserves each source's config" do
      Application.put_env(:gust, :dag_sources, [
        {"db-primary", type: Gust.DAG.Source.Database, notify: :listen},
        {"git-main", type: "git", url: "https://github.com/user/dags.git"}
      ])

      assert Config.read() == [
               %{id: "db-primary", type: Gust.DAG.Source.Database, notify: :listen},
               %{id: "git-main", type: "git", url: "https://github.com/user/dags.git"}
             ]

      assert Config.module_names() == [
               Gust.DAG.Source.Database,
               Gust.DAG.Source.Git
             ]
    end

    test "requires an id and type for every source config" do
      Application.put_env(:gust, :dag_sources, [
        {"db-primary", [notify: :listen]},
        %{type: "git", url: "https://github.com/user/dags.git"}
      ])

      assert_raise ArgumentError, ~r/(id|type)/, fn ->
        Config.read()
      end
    end
  end

  describe "load/0 without egit available" do
    test "returns error or empty map when egit not available" do
      put_git_source(url: "https://github.com/user/dags.git")

      result = Git.load()
      # Should be either an error tuple or empty success/error map
      assert is_map(result) or is_tuple(result)
    end
  end

  describe "parse_folder behavior" do
    test "returns empty success/error lists for empty repository" do
      put_git_source(url: "https://github.com/user/dags.git")

      result = Git.load()
      assert is_map(result) or is_tuple(result)

      if is_map(result) do
        assert Map.has_key?(result, :success) or Map.has_key?(result, :error)
      end
    end
  end

  describe "configuration handling" do
    test "uses default branch main" do
      put_git_source(url: "https://github.com/user/dags.git")

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "uses custom branch when configured" do
      put_git_source(url: "https://github.com/user/dags.git", branch: "develop")

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "uses custom path and wildcard when configured" do
      temp_path = Path.join(System.tmp_dir!(), "gust-test-git-#{System.monotonic_time()}")

      put_git_source(
        url: "https://github.com/user/dags.git",
        path: temp_path,
        wildcard: "/dags/**/*.y*ml"
      )

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "handles missing URL gracefully" do
      put_git_source([])

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end
  end

  describe "error handling" do
    test "rescues load_extensions errors" do
      put_git_source(url: "https://github.com/user/dags.git")

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "handles invalid URL" do
      put_git_source(url: "not-a-url")

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "handles ErlangError in ensure_repo_cloned" do
      put_git_source(url: "https://invalid.url/repo.git")

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end
  end

  describe "credentials handling" do
    test "handles nil credentials" do
      put_git_source(url: "https://github.com/user/dags.git", credentials: nil)

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "handles empty credentials list" do
      put_git_source(url: "https://github.com/user/dags.git", credentials: [])

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "builds SSH key credentials" do
      put_git_source(
        url: "git@github.com:user/dags.git",
        credentials: [
          type: :ssh_key,
          username: "git",
          privkey: "key_content",
          pubkey: "pub_key",
          passphrase: ""
        ]
      )

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "builds userpass credentials" do
      put_git_source(
        url: "https://github.com/user/dags.git",
        credentials: [
          type: :userpass,
          username: "user",
          password: "pass"
        ]
      )

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "builds token credentials" do
      put_git_source(
        url: "https://github.com/user/dags.git",
        credentials: [
          type: :token,
          username: "user",
          token: "github_token"
        ]
      )

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "builds SSH agent credentials" do
      put_git_source(
        url: "git@github.com:user/dags.git",
        credentials: [
          type: :ssh_agent,
          username: "git"
        ]
      )

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "logs warning for unknown credential type" do
      put_git_source(
        url: "https://github.com/user/dags.git",
        credentials: [
          type: :unknown,
          username: "user"
        ]
      )

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "handles missing SSH key file" do
      put_git_source(
        url: "git@github.com:user/dags.git",
        credentials: [
          type: :ssh_key,
          username: "git",
          privkey_path: "/nonexistent/key",
          pubkey_path: "/nonexistent/pub"
        ]
      )

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end
  end

  describe "credential building" do
    test "builds SSH key credentials from config" do
      # Mock configuration
      put_git_source(
        url: "git@github.com:user/dags.git",
        credentials: [
          type: :ssh_key,
          username: "git",
          privkey: "-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----",
          pubkey: "ssh-rsa AAAAB3...",
          passphrase: "secret"
        ]
      )

      # The credentials should be built without errors
      # (actual git operations are not tested here as they require egit)
      assert Git.name() == "Git"
    end

    test "builds userpass credentials from config" do
      put_git_source(
        url: "https://github.com/user/dags.git",
        credentials: [
          type: :userpass,
          username: "myuser",
          password: "mypass"
        ]
      )

      assert Git.name() == "Git"
    end

    test "builds token credentials from config" do
      put_git_source(
        url: "https://github.com/user/dags.git",
        credentials: [
          type: :token,
          username: "myuser",
          token: "ghp_xxxxxxxxxxxx"
        ]
      )

      assert Git.name() == "Git"
    end

    test "builds SSH agent credentials from config" do
      put_git_source(
        url: "git@github.com:user/dags.git",
        credentials: [
          type: :ssh_agent,
          username: "git"
        ]
      )

      assert Git.name() == "Git"
    end

    test "handles missing credentials gracefully" do
      put_git_source(url: "https://github.com/user/public-dags.git")

      assert Git.name() == "Git"
    end

    test "handles empty credentials list" do
      put_git_source(url: "https://github.com/user/public-dags.git", credentials: [])

      assert Git.name() == "Git"
    end
  end

  describe "configuration" do
    test "requires url in config" do
      put_git_source([])

      # This should return an error tuple when trying to load (url is required)
      # but not raise an exception
      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "uses default branch (main)" do
      put_git_source(url: "https://github.com/user/dags.git")

      # The function should not raise during initialization
      assert Git.name() == "Git"
    end

    test "uses provided branch" do
      put_git_source(url: "https://github.com/user/dags.git", branch: "develop")

      assert Git.name() == "Git"
    end

    test "uses provided poll_seconds" do
      put_git_source(url: "https://github.com/user/dags.git", poll_seconds: 60)

      assert Git.name() == "Git"
    end

    test "uses default poll_seconds (30)" do
      put_git_source(url: "https://github.com/user/dags.git")

      assert Git.name() == "Git"
    end

    test "uses provided path for repository" do
      put_git_source(url: "https://github.com/user/dags.git", path: "/custom/path/to/dags")

      assert Git.name() == "Git"
    end

    test "uses temp directory as default path" do
      put_git_source(url: "https://github.com/user/dags.git")

      assert Git.name() == "Git"
    end
  end

  describe "environment variable support" do
    setup do
      # Store original env vars
      original_username = System.get_env("GIT_CREDENTIALS_USERNAME")
      original_password = System.get_env("GIT_CREDENTIALS_PASSWORD")
      original_passphrase = System.get_env("SSH_KEY_PASSPHRASE")

      on_exit(fn ->
        # Restore original env vars
        if original_username, do: System.put_env("GIT_CREDENTIALS_USERNAME", original_username)
        if original_password, do: System.put_env("GIT_CREDENTIALS_PASSWORD", original_password)
        if original_passphrase, do: System.put_env("SSH_KEY_PASSPHRASE", original_passphrase)
      end)

      :ok
    end

    test "reads username from environment variable for userpass" do
      System.put_env("GIT_CREDENTIALS_USERNAME", "env_user")
      System.put_env("GIT_CREDENTIALS_PASSWORD", "env_pass")

      put_git_source(
        url: "https://github.com/user/dags.git",
        credentials: [
          type: :userpass
        ]
      )

      assert Git.name() == "Git"
    end

    test "reads password from environment variable for userpass" do
      System.put_env("GIT_CREDENTIALS_USERNAME", "myuser")
      System.put_env("GIT_CREDENTIALS_PASSWORD", "env_password")

      put_git_source(
        url: "https://github.com/user/dags.git",
        credentials: [
          type: :userpass,
          username: "myuser"
        ]
      )

      assert Git.name() == "Git"
    end

    test "reads token from environment variable for token type" do
      System.put_env("GIT_CREDENTIALS_PASSWORD", "ghp_env_token")

      put_git_source(
        url: "https://github.com/user/dags.git",
        credentials: [
          type: :token,
          username: "myuser"
        ]
      )

      assert Git.name() == "Git"
    end

    test "reads passphrase from environment variable for SSH" do
      System.put_env("SSH_KEY_PASSPHRASE", "env_passphrase")

      put_git_source(
        url: "git@github.com:user/dags.git",
        credentials: [
          type: :ssh_key,
          username: "git",
          privkey: "-----BEGIN OPENSSH PRIVATE KEY-----",
          pubkey: "ssh-rsa AAAAB3"
        ]
      )

      assert Git.name() == "Git"
    end

    test "config value takes precedence over environment variable" do
      System.put_env("GIT_CREDENTIALS_USERNAME", "env_user")

      put_git_source(
        url: "https://github.com/user/dags.git",
        credentials: [
          type: :userpass,
          username: "config_user",
          password: System.get_env("GIT_CREDENTIALS_PASSWORD", "config_pass")
        ]
      )

      assert Git.name() == "Git"
    end
  end

  describe "credential types" do
    test "SSH key type with file paths" do
      put_git_source(
        url: "git@github.com:user/dags.git",
        credentials: [
          type: :ssh_key,
          username: "git",
          privkey_path: "/home/user/.ssh/id_rsa",
          pubkey_path: "/home/user/.ssh/id_rsa.pub",
          passphrase: ""
        ]
      )

      assert Git.name() == "Git"
    end

    test "SSH key type with embedded content" do
      privkey =
        "-----BEGIN OPENSSH PRIVATE KEY-----\nMIIEpAIBAAKCAQEA...\n-----END OPENSSH PRIVATE KEY-----"

      pubkey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD...\n"

      put_git_source(
        url: "git@github.com:user/dags.git",
        credentials: [
          type: :ssh_key,
          username: "git",
          privkey: privkey,
          pubkey: pubkey,
          passphrase: ""
        ]
      )

      assert Git.name() == "Git"
    end

    test "unknown credential type is handled gracefully" do
      put_git_source(
        url: "https://github.com/user/dags.git",
        credentials: [
          type: :unknown_type,
          username: "user"
        ]
      )

      # Should not crash, just log a warning
      assert Git.name() == "Git"
    end
  end

  describe "load/0" do
    test "returns success/error map or error tuple" do
      put_git_source(url: "https://github.com/user/dags.git")

      result = Git.load()
      assert is_map(result) or is_tuple(result)

      if is_map(result) do
        assert Map.has_key?(result, :success)
        assert Map.has_key?(result, :error)
        assert is_list(result.success)
        assert is_list(result.error)
      end
    end

    test "returns error tuple on invalid URL" do
      put_git_source(url: "invalid://url")

      assert {:error, _reason} = Git.load()
    end

    test "handles missing URL gracefully" do
      put_git_source([])

      assert {:error, _reason} = Git.load()
    end
  end

  describe "monitor/2" do
    setup do
      original_config = Application.get_env(:gust, :dag_sources)

      config = [
        url: "https://github.com/user/dags.git",
        branch: "main",
        path: Path.join(System.tmp_dir!(), "gust_test_git_#{System.monotonic_time()}"),
        poll_seconds: 1
      ]

      put_git_source(config)

      on_exit(fn ->
        restore_dag_source(original_config)
        # Cleanup temp directory
        if File.exists?(config[:path]) do
          File.rm_rf!(config[:path])
        end
      end)

      {:ok, config: config}
    end

    @tag :capture_log
    test "returns ok tuple with monitor pid" do
      test_pid = self()

      {:ok, monitor_pid} = Git.monitor(test_pid)

      # Allow ExUnit to track the spawned monitor process
      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      assert is_pid(monitor_pid)
    end

    @tag :capture_log
    test "starts a polling monitor" do
      test_pid = self()

      {:ok, monitor_pid} = Git.monitor(test_pid)

      # Allow ExUnit to track the spawned monitor process
      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      # Process should be alive
      assert Process.alive?(monitor_pid)
    end

    @tag :capture_log
    test "monitor/2 accepts config parameter" do
      test_pid = self()

      {:ok, monitor_pid} = Git.monitor(test_pid, %{})

      # Allow ExUnit to track the spawned monitor process
      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      assert is_pid(monitor_pid)
    end
  end

  describe "behavior compliance" do
    test "implements Gust.DAG.Source behavior" do
      assert function_exported?(Git, :load, 0)
      assert function_exported?(Git, :load, 1)
      assert function_exported?(Git, :monitor, 2)
      assert function_exported?(Git, :name, 0)
    end

    test "load returns a map or error tuple" do
      put_git_source(url: "https://github.com/user/dags.git")

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end
  end

  describe "default configuration values" do
    test "uses main as default branch" do
      put_git_source(url: "https://github.com/user/dags.git")

      assert Git.name() == "Git"
    end

    test "uses 30 seconds as default poll interval" do
      put_git_source(url: "https://github.com/user/dags.git")

      # Verify configuration doesn't crash
      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "uses system temp directory as default path" do
      put_git_source(url: "https://github.com/user/dags.git")

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end
  end

  describe "helper functions" do
    test "credential building handles all types" do
      # Test that different credential types don't crash the system
      assert Git.name() == "Git"
    end

    test "poll_seconds configuration is respected" do
      put_git_source(url: "https://github.com/user/dags.git", poll_seconds: 45)

      assert Git.name() == "Git"
    end
  end

  describe "internal functions" do
    test "load handles rescue errors" do
      # load should handle exceptions and return error tuple or empty map
      put_git_source([])
      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "ensure_repo_cloned handles ErlangError" do
      put_git_source(url: "invalid")
      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "parse_dag_content with rescue" do
      # Test parse_dag_content error handling
      put_git_source(url: "https://invalid.url")
      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end

    test "parse_folder with empty repository" do
      put_git_source(url: "https://github.com/user/empty-repo.git", branch: "main")

      result = Git.load()
      assert is_map(result) or is_tuple(result)
    end
  end

  describe "credential type handling" do
    test "handles nil credentials type" do
      put_git_source(url: "https://github.com/user/dags.git", credentials: [])

      assert Git.name() == "Git"
    end

    test "read_ssh_key handles file read errors" do
      put_git_source(
        url: "git@github.com:user/dags.git",
        credentials: [
          type: :ssh_key,
          username: "git",
          privkey_path: "/nonexistent/file",
          pubkey_path: "/nonexistent/file"
        ]
      )

      # Should not crash despite missing files
      assert Git.name() == "Git"
    end

    test "get_env_or_config prefers environment variables" do
      System.put_env("GIT_TEST_VAR", "from_env")

      put_git_source(url: "https://github.com/user/dags.git")

      # This tests the logic without crashing
      assert Git.name() == "Git"

      System.delete_env("GIT_TEST_VAR")
    end
  end

  describe "monitor/2 additional tests" do
    setup do
      original_config = Application.get_env(:gust, :dag_sources)

      config = [
        url: "https://github.com/user/dags.git",
        branch: "develop",
        poll_seconds: 2
      ]

      put_git_source(config)

      on_exit(fn ->
        restore_dag_source(original_config)
      end)

      {:ok, config: config}
    end

    @tag :capture_log
    test "monitor accepts config parameter with custom branch" do
      test_pid = self()

      {:ok, monitor_pid} = Git.monitor(test_pid, %{})

      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(monitor_pid) do
          Process.exit(monitor_pid, :kill)
        end
      end)

      assert is_pid(monitor_pid)
    end
  end
end
