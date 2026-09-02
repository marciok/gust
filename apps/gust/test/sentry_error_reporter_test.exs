defmodule Gust.SentryErrorReporterTest do
  use ExUnit.Case, async: true

  test "returns the external error URL" do
    assert {:ok, "https://errors.example.com/events/event-123"} =
             Gust.SentryErrorReporter.capture(%RuntimeError{message: "boom"}, [], %{})
  end
end
