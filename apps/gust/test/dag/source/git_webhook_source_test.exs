defmodule Gust.DAG.Source.GitWebhookSourceTest do
  use ExUnit.Case, async: false

  alias Gust.DAG.Source.GitWebhook
  alias Gust.DAG.Source.GitWebhook.Monitor

  import Gust.ApplicationEnvHelpers

  setup :init_dag_source

  setup do
    previous_git = System.get_env("GIT_WEBHOOK_SECRET")
    previous_gh = System.get_env("GITHUB_WEBHOOK_SECRET")
    previous_gl = System.get_env("GITLAB_WEBHOOK_SECRET")
    previous_gitea = System.get_env("GITEA_WEBHOOK_SECRET")

    on_exit(fn ->
      restore_env("GIT_WEBHOOK_SECRET", previous_git)
      restore_env("GITHUB_WEBHOOK_SECRET", previous_gh)
      restore_env("GITLAB_WEBHOOK_SECRET", previous_gl)
      restore_env("GITEA_WEBHOOK_SECRET", previous_gitea)
    end)

    :ok
  end

  test "monitor starts with platform-specific secret when webhook secret is not set" do
    System.delete_env("GIT_WEBHOOK_SECRET")
    System.put_env("GITHUB_WEBHOOK_SECRET", "gh-secret")

    {:ok, pid} = GitWebhook.monitor(self(), webhook_platforms: [:github])

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    assert Process.alive?(pid)
  end

  test "monitor starts when at least one configured platform has a secret" do
    System.delete_env("GIT_WEBHOOK_SECRET")
    System.delete_env("GITHUB_WEBHOOK_SECRET")
    System.put_env("GITLAB_WEBHOOK_SECRET", "gl-secret")

    {:ok, pid} = GitWebhook.monitor(self(), webhook_platforms: [:github, :gitlab])

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    assert Process.alive?(pid)
  end

  test "monitor returns error when no shared or platform-specific secret exists" do
    System.delete_env("GIT_WEBHOOK_SECRET")
    System.delete_env("GITHUB_WEBHOOK_SECRET")
    System.delete_env("GITLAB_WEBHOOK_SECRET")
    System.delete_env("GITEA_WEBHOOK_SECRET")

    assert {:error, message} = GitWebhook.monitor(self(), webhook_platforms: [:github])

    assert message =~ "requires :webhook_secret"
  end

  test "monitor suppresses reload requests while paused and replays on resume" do
    test_pid = self()

    reload_fun = fn _loader_pid, _payload, snapshot ->
      send(test_pid, :reload_called)
      snapshot
    end

    {:ok, pid} = Monitor.start_link(self(), "secret", reload_fun)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    assert :ok = GenServer.call(pid, :pause)

    send(pid, {:git_webhook_reload, %{"repo" => "a"}})
    refute_receive :reload_called, 100

    assert :ok = GenServer.call(pid, :resume)
    assert_receive :reload_called
  end

  test "monitor triggers reload immediately when running" do
    test_pid = self()

    reload_fun = fn _loader_pid, _payload, snapshot ->
      send(test_pid, :reload_called)
      snapshot
    end

    {:ok, pid} = Monitor.start_link(self(), "secret", reload_fun)

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    send(pid, {:git_webhook_reload, %{"repo" => "a"}})
    assert_receive :reload_called
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
