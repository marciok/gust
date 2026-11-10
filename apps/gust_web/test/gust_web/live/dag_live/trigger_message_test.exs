defmodule GustWeb.DagLive.TriggerMessageTest do
  use ExUnit.Case, async: true

  alias Gust.Flows.{Dag, Run}
  alias GustWeb.DagLive.TriggerMessage

  @run %Run{id: 42}
  @enabled %Dag{name: "my_dag", enabled: true}
  @paused %Dag{name: "my_dag", enabled: false}

  describe "flash/3" do
    test "enabled dag returns an info flash" do
      assert {:info, "Run 42 triggered"} == TriggerMessage.flash(@enabled, @run)
    end

    test "enabled dag with pinned history returns a warning with the unpin hint" do
      assert {:warning, "Run 42 triggered. Unpin your history to view it."} ==
               TriggerMessage.flash(@enabled, @run, pinned?: true)
    end

    test "paused dag returns a warning mentioning the dag is paused" do
      assert {:warning,
              "Run 42 created, but DAG my_dag is paused. It will start once the DAG is enabled."} ==
               TriggerMessage.flash(@paused, @run)
    end

    test "paused dag with pinned history mentions both" do
      assert {:warning, message} = TriggerMessage.flash(@paused, @run, pinned?: true)
      assert message =~ "DAG my_dag is paused."
      assert message =~ "Unpin your history to view it."
    end
  end
end
