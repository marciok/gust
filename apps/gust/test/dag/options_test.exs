defmodule DAG.OptionsTest do
  use ExUnit.Case, async: false
  import Gust.ApplicationEnvHelpers
  alias Gust.DAG.Definition
  alias Gust.DAG.Options

  describe "validate/1" do
    test "accepts the known options" do
      options = [
        schedule: "* * * * *",
        on_finished_callback: :done,
        runs: [retention: [max_count: 10]]
      ]

      assert {:ok, ^options} = Options.validate(options)
    end

    test "accepts runs without retention" do
      assert {:ok, [runs: []]} == Options.validate(runs: [])
    end

    test "rejects unknown keys" do
      assert {:error,
              "unknown keys [:foo] in [foo: 1], the allowed keys are: [:schedule, :on_finished_callback, :runs]"} ==
               Options.validate(foo: 1)
    end

    test "rejects options that are not a keyword list" do
      assert {:error, "DAG options must be a keyword list, got: \"nope\""} ==
               Options.validate("nope")
    end

    test "accepts crontab schedules and a nil schedule" do
      for schedule <- ["* * * * *", "@daily", nil] do
        assert {:ok, _options} = Options.validate(schedule: schedule)
      end
    end

    test "rejects an invalid schedule" do
      assert {:error, "invalid schedule \"bla\": " <> _reason} = Options.validate(schedule: "bla")
    end

    test "rejects a schedule that is not a string" do
      assert {:error, "schedule must be a crontab expression string, got: 5"} ==
               Options.validate(schedule: 5)
    end

    test "rejects an on_finished_callback that is not a function name" do
      assert {:error, "on_finished_callback must be a function name, got: 5"} ==
               Options.validate(on_finished_callback: 5)
    end

    test "rejects runs that is not a keyword list" do
      assert {:error, "runs must be a keyword list, got: :sequential"} ==
               Options.validate(runs: :sequential)
    end

    test "rejects unknown runs keys" do
      assert {:error,
              "unknown keys [:foo] in runs [foo: true], the allowed keys are: [:retention]"} ==
               Options.validate(runs: [foo: true])
    end

    test "rejects retention that is not a keyword list" do
      assert {:error, "runs retention must be a keyword list, got: :keep_forever"} ==
               Options.validate(runs: [retention: :keep_forever])
    end

    test "requires max_count in retention" do
      assert {:error, "runs retention requires max_count"} ==
               Options.validate(runs: [retention: []])
    end

    test "rejects a non-integer max_count" do
      assert {:error, "runs retention max_count must be a positive integer, got: \"10\""} ==
               Options.validate(runs: [retention: [max_count: "10"]])
    end
  end

  describe "from_json/1" do
    test "converts known keys and ignores unknown top-level keys" do
      json = %{
        "schedule" => nil,
        "on_finished_callback" => "done",
        "runs" => %{"retention" => %{"max_count" => 10}},
        "unexpected" => "value"
      }

      assert {:ok,
              [
                on_finished_callback: "done",
                schedule: nil,
                runs: [retention: [max_count: 10]]
              ]} == Options.from_json(json)
    end

    test "converts options without runs" do
      assert {:ok, [schedule: "* * * * *"]} == Options.from_json(%{"schedule" => "* * * * *"})
    end

    test "drops a null runs option" do
      assert {:ok, [schedule: nil]} == Options.from_json(%{"schedule" => nil, "runs" => nil})
    end

    test "rejects unknown runs keys" do
      assert {:error, "unknown key \"concurrency\" in runs"} ==
               Options.from_json(%{"runs" => %{"concurrency" => "sequential"}})
    end

    test "validates the converted options" do
      assert {:error, "runs retention max_count must be a positive integer, got: 0"} ==
               Options.from_json(%{"runs" => %{"retention" => %{"max_count" => 0}}})
    end
  end

  describe "definition_error/2" do
    test "builds a compile error and a matching error message" do
      assert {%CompileError{file: "/dags/a.ex", description: "invalid DAG options: bad"},
              [%{message: "invalid DAG options: bad", severity: :error, file: "/dags/a.ex"}]} =
               Options.definition_error("/dags/a.ex", "bad")
    end
  end

  describe "warnings/2" do
    test "warns about a retention without prune_schedule" do
      replace_env(:runs, [])

      assert [%{message: message, severity: :warning, file: "/dags/a.ex"}] =
               Options.warnings([runs: [retention: [max_count: 10]]], "/dags/a.ex")

      assert message =~ "pruning is off"
      assert message =~ "prune_schedule"
    end

    test "warns about a retention with an invalid prune_schedule" do
      replace_env(:runs, prune_schedule: "nope")

      assert [%{severity: :warning}] =
               Options.warnings([runs: [retention: [max_count: 10]]], "/dags/a.ex")
    end

    test "doesn't warn when prune_schedule is set" do
      replace_env(:runs, prune_schedule: "@daily")

      assert [] == Options.warnings([runs: [retention: [max_count: 10]]], "/dags/a.ex")
    end

    test "doesn't warn without a retention" do
      replace_env(:runs, [])

      assert [] == Options.warnings([schedule: "* * * * *"], "/dags/a.ex")
    end
  end

  describe "max_count/1" do
    test "returns the retention max_count" do
      dag_def = %Definition{options: [runs: [retention: [max_count: 10]]]}
      assert 10 == Options.max_count(dag_def)
    end

    test "returns nil without retention" do
      assert nil == Options.max_count(%Definition{options: [schedule: "* * * * *"]})
      assert nil == Options.max_count(%Definition{options: [runs: []]})
    end
  end
end
