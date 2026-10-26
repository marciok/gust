defmodule CompileErrorDag do
  use Gust.DSL

  task :orphan do
    undefined_variable
  end
end
