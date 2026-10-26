defmodule Gust.FileMonitor.SystemFs do
  @moduledoc false
  @behaviour Gust.FileMonitor

  # coveralls-ignore-start

  @doc """
  Starts a `FileSystem` watcher with `opts`.

  `:file_system` is a dev/test-only dependency, so `FileSystem` is called through
  `apply/3`. A direct call would make the compiler warn about an undefined module
  wherever `:file_system` isn't present, such as `:prod`.
  """
  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  def start_link(opts), do: apply(FileSystem, :start_link, [opts])

  @doc """
  Subscribes the caller to the file events of `server`.

  Calls `FileSystem` through `apply/3` for the same reason as `start_link/1`.
  """
  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  def watch(server), do: apply(FileSystem, :subscribe, [server])

  @doc """
  Returns whether this OS has a working `file_system` backend, such as
  `inotify-tools` on Linux, without starting a watcher.

  Returns `false` when `:file_system` isn't loaded. Calls `FileSystem.Backend`
  through `apply/3` for the same reason as `start_link/1`.
  """
  @impl true
  def available?,
    do: Code.ensure_loaded?(FileSystem.Backend) and match?({:ok, _backend}, backend())

  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  defp backend, do: apply(FileSystem.Backend, :backend, [nil])

  # coveralls-ignore-stop
end
