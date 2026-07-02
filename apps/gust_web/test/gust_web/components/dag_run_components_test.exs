defmodule GustWeb.DagRunComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GustWeb.DagRunComponents

  describe "status_badge/1" do
    test "renders status-specific badge classes" do
      [
        created: "badge-info",
        enqueued: "badge-info",
        running: "badge-info",
        succeeded: "badge-success",
        failed: "badge-error",
        skipped: "badge-warning",
        retrying: "badge-warning",
        waiting: "badge-warning",
        upstream_failed: "badge-warning"
      ]
      |> Enum.each(fn {status, badge_class} ->
        document =
          render_component(&DagRunComponents.status_badge/1, id: "status-badge", status: status)
          |> LazyHTML.from_fragment()

        assert [_badge] =
                 LazyHTML.query(document, "#status-badge.badge.badge-outline.#{badge_class}")
                 |> LazyHTML.to_tree()
      end)
    end
  end

  describe "log_badge/1" do
    test "renders level-specific badge classes" do
      [
        {"debug", "badge-info"},
        {"info", "badge-info"},
        {"warn", "badge-warning"},
        {"error", "badge-error"}
      ]
      |> Enum.each(fn {level, badge_class} ->
        document =
          render_component(&DagRunComponents.log_badge/1, level: level)
          |> LazyHTML.from_fragment()

        assert [{"div", attrs, [rendered_level]}] =
                 LazyHTML.query(document, ".badge.badge-soft.#{badge_class}")
                 |> LazyHTML.to_tree()

        assert String.trim(rendered_level) == level
        assert {"class", _classes} = List.keyfind(attrs, "class", 0)
      end)
    end
  end

  describe "task_cell/1" do
    test "renders status classes" do
      [
        :created,
        :enqueued,
        :running,
        :succeeded,
        :failed,
        :upstream_failed
      ]
      |> Enum.each(fn status ->
        document =
          render_component(&DagRunComponents.task_cell/1, id: "task-cell", status: status)
          |> LazyHTML.from_fragment()

        assert [_cell] =
                 LazyHTML.query(document, "#task-cell.task-grid-cell.status-#{status}.active")
                 |> LazyHTML.to_tree()
      end)
    end

    test "renders status and selected classes" do
      document =
        render_component(&DagRunComponents.task_cell/1,
          id: "task-cell",
          status: :succeeded,
          selected: true
        )
        |> LazyHTML.from_fragment()

      assert [_cell] =
               LazyHTML.query(
                 document,
                 "#task-cell.task-grid-cell.status-succeeded.active.selected"
               )
               |> LazyHTML.to_tree()
    end

    test "renders status-none when status is absent" do
      document =
        render_component(&DagRunComponents.task_cell/1, id: "empty-cell")
        |> LazyHTML.from_fragment()

      assert [_cell] =
               LazyHTML.query(document, "#empty-cell.task-grid-cell.status-none")
               |> LazyHTML.to_tree()
    end
  end

  describe "interactive_task_cell/1" do
    test "renders linked task data when task exists" do
      document =
        render_component(&DagRunComponents.interactive_task_cell/1,
          run_id: 42,
          name: "load_data",
          navigate: "/runs/42/tasks/load_data",
          task_data: %{selected: true, status: :running}
        )
        |> LazyHTML.from_fragment()

      assert [_link] =
               LazyHTML.query(document, "a[href='/runs/42/tasks/load_data']")
               |> LazyHTML.to_tree()

      assert [_cell] =
               LazyHTML.query(
                 document,
                 "#load_data-at-run-42.task-grid-cell.status-running.active.selected"
               )
               |> LazyHTML.to_tree()
    end

    test "renders an unlinked empty cell when task data is absent" do
      document =
        render_component(&DagRunComponents.interactive_task_cell/1,
          run_id: 42,
          name: "missing_task",
          navigate: "/runs/42/tasks/missing_task"
        )
        |> LazyHTML.from_fragment()

      assert [] =
               LazyHTML.query(document, "a[href='/runs/42/tasks/missing_task']")
               |> LazyHTML.to_tree()

      assert [_cell] =
               LazyHTML.query(document, "#missing_task-at-run-42.task-grid-cell.status-none")
               |> LazyHTML.to_tree()
    end
  end
end
