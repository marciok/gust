defmodule Gust.FileMonitor.SystemFs do
  @moduledoc false
  @behaviour Gust.FileMonitor

  # Note: To avoid compile-time warnings in environments where `:file_system` is not present
  # (e.g., `:prod`), we use `apply/3` instead of direct function calls.
  #
  # This ensures the compiler does not resolve `FileSystem.start_link/1` or
  # `FileSystem.subscribe/1` unless the module is actually loaded at runtime.

  # coveralls-ignore-start
  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  def start_link(opts), do: apply(FileSystem, :start_link, [opts])

  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.Apply
  def watch(server), do: apply(FileSystem, :subscribe, [server])

  # coveralls-ignore-stop
end
