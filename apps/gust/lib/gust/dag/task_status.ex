defmodule Gust.DAG.TaskStatus do
  @moduledoc false

  @cancellable_statuses [:running, :retrying, :waiting]
  @restartable_statuses [:failed, :succeeded]

  def cancellable_statuses, do: @cancellable_statuses
  def restartable_statuses, do: @restartable_statuses

  def cancellable?(status), do: status in @cancellable_statuses
  def mapped_cancellable?(status), do: cancellable?(status) or status == :created
  def restartable?(status), do: status in @restartable_statuses
end
