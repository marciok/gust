defmodule GustShell.TemplateTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias GustShell.Template

  import Gust.FlowsFixtures

  describe "render/2" do
    test "binds run_id and params" do
      task = %{run_id: 7, params: %{"target" => "x86_64"}}

      assert Template.render(~s(build <%= run_id %> <%= params["target"] %>), task) ==
               "build 7 x86_64"
    end

    test "defaults params to an empty map" do
      assert Template.render(~s{<%= inspect(params) %>}, %{run_id: 1, params: nil}) == "%{}"
    end

    test "aliases Gust.Flows as Flows" do
      assert Template.render("<%= inspect(Flows) %>", %{run_id: 1, params: %{}}) ==
               "Gust.Flows"
    end

    test "keeps Kernel functions and macros available" do
      template = ~s{<%= if params["debug"], do: "-v", else: to_string(run_id) %>}

      assert Template.render(template, %{run_id: 3, params: %{}}) == "3"
      assert Template.render(template, %{run_id: 3, params: %{"debug" => true}}) == "-v"
    end

    test "does not load the run when run_params is not used" do
      # No sandbox checkout here, so any database query would fail.
      assert Template.render("echo <%= run_id %>", %{run_id: -1, params: %{}}) == "echo -1"
    end

    test "leaves text without tags unchanged" do
      assert Template.render("echo 'a%b'", %{run_id: 1, params: %{}}) == "echo 'a%b'"
    end
  end

  describe "validate!/1" do
    test "accepts valid templates" do
      assert Template.validate!(~s(echo <%= params["name"] %>)) == :ok
    end

    for template <- ["echo <%= params[", "echo <%= if true do %>", "echo <%= 1 +"] do
      test "rejects #{inspect(template)}" do
        assert_raise ArgumentError, ~r/invalid template/, fn ->
          Template.validate!(unquote(template))
        end
      end
    end
  end

  describe "secret!/1" do
    setup do
      :ok = Sandbox.checkout(Gust.Repo)
    end

    test "returns the secret value" do
      secret_fixture(%{name: "SHELL_TOKEN", value: "s3cr3t"})

      assert Template.render(~s{<%= secret!("SHELL_TOKEN") %>}, %{run_id: 1, params: %{}}) ==
               "s3cr3t"
    end

    test "raises when the secret does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Template.render(~s{<%= secret!("MISSING") %>}, %{run_id: 1, params: %{}})
      end
    end
  end

  describe "run lookups" do
    setup do
      :ok = Sandbox.checkout(Gust.Repo)
      dag = dag_fixture()
      run = run_fixture(%{dag_id: dag.id, status: :running, params: %{"target" => "arm64"}})

      %{run: run}
    end

    test "run_params reads the params the run was triggered with", %{run: run} do
      template = ~s{build --target <%= run_params["target"] %> <%= inspect(params) %>}

      assert Template.render(template, %{run_id: run.id, params: %{"item" => 1}}) ==
               ~s(build --target arm64 %{"item" => 1})
    end

    test "returns the saved result of a task in the same run", %{run: run} do
      task_fixture(%{
        run_id: run.id,
        name: "read_version",
        result: %{stdout: "1.2.3\n", stderr: "", exit_code: 0}
      })

      template = ~s{<%= String.trim(task_result!("read_version")["stdout"]) %>}

      assert Template.render(template, %{run_id: run.id, params: %{}}) == "1.2.3"
    end

    test "raises when the task is not in the run", %{run: run} do
      assert_raise Ecto.NoResultsError, fn ->
        Template.render(~s{<%= task_result!("missing") %>}, %{run_id: run.id, params: %{}})
      end
    end

    test "returns an empty map when the task did not save a result", %{run: run} do
      task_fixture(%{run_id: run.id, name: "unsaved"})

      assert Template.render(~s{<%= inspect(task_result!("unsaved")) %>}, %{
               run_id: run.id,
               params: %{}
             }) == "%{}"

      template = ~s{<%= task_result!("unsaved")["stdout"] || raise "unsaved saved no output" %>}

      assert_raise RuntimeError, "unsaved saved no output", fn ->
        Template.render(template, %{run_id: run.id, params: %{}})
      end
    end
  end
end
