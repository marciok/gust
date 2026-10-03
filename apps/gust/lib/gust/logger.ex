defmodule Gust.LoggerFormatter do
  @moduledoc false

  def format(level, message, timestamp, metadata) do
    location =
      case {metadata[:file], metadata[:line]} do
        {file, line} when is_list(file) and is_integer(line) ->
          "[#{file}:#{line}]"

        _ ->
          ""
      end

    "#{convert(timestamp)} [#{level}] #{message} #{location}\n"
  rescue
    _ -> "#{convert(timestamp)} [#{level}] #{message}\n"
  end

  def convert({{y, m, d}, {h, min, s, ms}}) do
    :io_lib.format("~4..0B~2..0B~2..0B ~2..0B:~2..0B:~2..0B.~3..0B", [y, m, d, h, min, s, ms])
  end
end
