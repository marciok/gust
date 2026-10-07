defmodule Gust.DAG.Source.ValidateTest do
  use ExUnit.Case, async: false

  import Gust.ApplicationEnvHelpers

  alias Gust.DAG.Source
  alias Gust.DAG.Source.Config
  alias Gust.DAG.Source.Folder

  setup :init_dag_source

  setup do
    original = Application.get_env(:gust, :dags_folder)
    on_exit(fn -> Application.put_env(:gust, :dags_folder, original) end)
    %{missing: Path.join(System.tmp_dir!(), "missing-#{System.unique_integer([:positive])}")}
  end

  test "git-only config boots without a dags folder", %{missing: missing} do
    Application.put_env(:gust, :dags_folder, missing)
    put_git_source(url: "https://example.com/repo.git")

    assert :ok = Source.validate_all!("prod", Config.read())
  end

  test "folder source with a missing folder raises with the source id", %{missing: missing} do
    put_folder_source(folder: missing)

    assert_raise ArgumentError, ~r/test-folder.*#{Regex.escape(missing)}/, fn ->
      Source.validate_all!("prod", Config.read())
    end
  end

  test "folder source is not validated in test", %{missing: missing} do
    put_folder_source(folder: missing)
    assert :ok = Source.validate_all!("test", Config.read())
  end

  test "folder/1 prefers the source folder over the legacy dags_folder" do
    Application.put_env(:gust, :dags_folder, "/legacy")
    assert Folder.folder(%{folder: "/source"}) == "/source"
    assert Folder.folder(folder: "/source") == "/source"
  end

  test "legacy dags_folder is the fallback and default source uses it" do
    Application.put_env(:gust, :dags_folder, "/legacy")
    assert Folder.folder(%{}) == "/legacy"

    Application.delete_env(:gust, :dag_sources)
    [config] = Config.read()
    assert Folder.folder(config) == "/legacy"
  end
end
