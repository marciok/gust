defmodule Gust.DAG.Run.ErrorReporter.ExternalReferenceTest do
  use ExUnit.Case, async: true

  alias Gust.DAG.Run.ErrorReporter.ExternalReference

  test "accepts absolute HTTP and HTTPS URLs" do
    assert ExternalReference.valid?("http://errors.example.com/events/1")
    assert ExternalReference.valid?("https://errors.example.com/events/1")
  end

  test "rejects non-HTTP URLs and non-binary values" do
    refute ExternalReference.valid?("ftp://errors.example.com/events/1")
    refute ExternalReference.valid?("/events/1")
    refute ExternalReference.valid?(nil)
  end
end
