defimpl Phoenix.HTML.Safe, for: Gust.Flows.Task do
  def to_iodata(task) do
    Phoenix.HTML.Safe.to_iodata("Task #{task.name}")
  end
end

defimpl Phoenix.HTML.Safe, for: Gust.Flows.Run do
  def to_iodata(run) do
    Phoenix.HTML.Safe.to_iodata("Run #{run.id}")
  end
end
