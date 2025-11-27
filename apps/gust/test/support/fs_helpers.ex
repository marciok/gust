defmodule Gust.FSHelpers do
  @moduledoc false
  def make_rand_dir!(prefix) do
    base = System.tmp_dir!()

    uniq =
      "#{prefix}_#{System.monotonic_time()}_#{System.unique_integer([:positive, :monotonic])}"

    path = Path.join(base, uniq)
    File.mkdir_p!(path)
    path
  end
end
