defmodule Gust.FlowsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Gust.Flows` context.
  """

  def secret_fixture(attrs \\ %{}) do
    {:ok, secret} =
      attrs
      |> Enum.into(%{
        name: "SOME_NAME",
        value: "some value",
        value_type: :string
      })
      |> Gust.Flows.create_secret()

    secret
  end

  def dag_fixture(attrs \\ %{}) do
    {:ok, dag} =
      attrs
      |> Enum.into(%{
        name: "some_name"
      })
      |> Gust.Flows.create_dag()

    dag
  end

  def run_fixture(attrs \\ %{}) do
    {:ok, run} =
      Gust.Flows.create_test_run(attrs)

    run
  end

  def task_fixture(attrs \\ %{}) do
    {:ok, task} =
      Gust.Flows.create_test_task(attrs)

    task
  end

  def log_fixture(attrs \\ %{}) do
    {:ok, log} =
      Gust.Flows.create_log(attrs)

    log
  end
end
