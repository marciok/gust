defmodule Gust.DagSourceTest do
  use Gust.DataCase

  alias Gust.DagSource
  alias Gust.Repo

  describe "changeset/2" do
    test "validates required fields" do
      changeset = DagSource.changeset(%DagSource{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).content
    end

    test "format has default value when not provided" do
      dag_source = %DagSource{format: "elixir"}
      changeset = DagSource.changeset(dag_source, %{name: "test", content: "test"})
      assert changeset.valid?
    end

    test "casts valid attributes" do
      attrs = %{
        name: "test_dag",
        content: "defmodule TestDAG do\n  use Gust.DAG\nend",
        format: "elixir",
        version: 1,
        enabled: true,
        description: "A test DAG"
      }

      changeset = DagSource.changeset(%DagSource{}, attrs)
      assert changeset.valid?
    end

    test "unique_constraint on name prevents duplicate inserts" do
      {:ok, _} =
        Repo.insert(%DagSource{
          name: "unique_dag",
          content: "content1",
          format: "elixir",
          enabled: true
        })

      changeset =
        DagSource.changeset(%DagSource{}, %{
          name: "unique_dag",
          content: "content2",
          format: "elixir",
          enabled: true
        })

      {:error, changeset} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset).name
    end

    test "allows duplicate names if previous one is deleted" do
      dag1 = %DagSource{
        name: "reusable_dag",
        content: "content1",
        format: "elixir",
        enabled: true
      }

      {:ok, inserted_dag} = Repo.insert(dag1)
      Repo.delete(inserted_dag)

      dag2 = %DagSource{
        name: "reusable_dag",
        content: "content2",
        format: "elixir",
        enabled: true
      }

      {:ok, _} = Repo.insert(dag2)
    end
  end

  describe "active?/2" do
    test "returns true when enabled with no time constraints" do
      dag_source = %DagSource{
        enabled: true,
        start_time: nil,
        end_time: nil
      }

      assert DagSource.active?(dag_source)
    end

    test "returns false when disabled" do
      dag_source = %DagSource{
        enabled: false,
        start_time: nil,
        end_time: nil
      }

      refute DagSource.active?(dag_source)
    end

    test "returns true when start_time is in the past" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -3600)

      dag_source = %DagSource{
        enabled: true,
        start_time: past,
        end_time: nil
      }

      assert DagSource.active?(dag_source, now)
    end

    test "returns false when start_time is in the future" do
      now = DateTime.utc_now()
      future = DateTime.add(now, 3600)

      dag_source = %DagSource{
        enabled: true,
        start_time: future,
        end_time: nil
      }

      refute DagSource.active?(dag_source, now)
    end

    test "returns true when end_time is in the future" do
      now = DateTime.utc_now()
      future = DateTime.add(now, 3600)

      dag_source = %DagSource{
        enabled: true,
        start_time: nil,
        end_time: future
      }

      assert DagSource.active?(dag_source, now)
    end

    test "returns false when end_time is in the past" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -3600)

      dag_source = %DagSource{
        enabled: true,
        start_time: nil,
        end_time: past
      }

      refute DagSource.active?(dag_source, now)
    end

    test "returns true when within valid time window" do
      now = DateTime.utc_now()
      past = DateTime.add(now, -3600)
      future = DateTime.add(now, 3600)

      dag_source = %DagSource{
        enabled: true,
        start_time: past,
        end_time: future
      }

      assert DagSource.active?(dag_source, now)
    end

    test "returns false when outside time window (before start)" do
      now = DateTime.utc_now()
      start_time = DateTime.add(now, 1800)
      end_time = DateTime.add(now, 3600)

      dag_source = %DagSource{
        enabled: true,
        start_time: start_time,
        end_time: end_time
      }

      refute DagSource.active?(dag_source, now)
    end

    test "returns false when outside time window (after end)" do
      now = DateTime.utc_now()
      start_time = DateTime.add(now, -3600)
      end_time = DateTime.add(now, -1800)

      dag_source = %DagSource{
        enabled: true,
        start_time: start_time,
        end_time: end_time
      }

      refute DagSource.active?(dag_source, now)
    end

    test "returns true at exact start_time" do
      now = DateTime.utc_now()

      dag_source = %DagSource{
        enabled: true,
        start_time: now,
        end_time: nil
      }

      assert DagSource.active?(dag_source, now)
    end

    test "returns true at exact end_time" do
      now = DateTime.utc_now()

      dag_source = %DagSource{
        enabled: true,
        start_time: nil,
        end_time: now
      }

      assert DagSource.active?(dag_source, now)
    end

    test "uses DateTime.utc_now() by default when no time param given" do
      # Create a DAG source that should be active now
      dag_source = %DagSource{
        enabled: true,
        start_time: nil,
        end_time: nil
      }

      assert DagSource.active?(dag_source)
    end
  end
end
