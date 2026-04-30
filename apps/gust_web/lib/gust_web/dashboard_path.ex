defmodule GustWeb.DashboardPath do
  @moduledoc false
  @base Application.compile_env(:gust_web, :dashboard_path, "/")

  @doc """
  Configured dashboard base path. Returned as set in config (default `"/"`).

  Concat consumers should strip the trailing slash before joining: see
  `GustWeb.DashboardPath.sigil_g/2` and `GustWeb.Layouts.asset_path/2`.
  """
  def base, do: @base

  defmacro sigil_g({:<<>>, _, pieces}, []) do
    base = String.trim_trailing(@base, "/")
    pieces = Enum.map(pieces, &to_param_piece/1)

    quote do
      unquote(base) <> unquote({:<<>>, [], pieces})
    end
  end

  defp to_param_piece({:"::", meta, [{{:., _, [Kernel, :to_string]}, interp_meta, [expr]}, type]}) do
    to_param_call = {{:., [], [Phoenix.Param, :to_param]}, [], [expr]}
    to_string_call = {{:., [], [Kernel, :to_string]}, interp_meta, [to_param_call]}
    {:"::", meta, [to_string_call, type]}
  end

  defp to_param_piece(literal), do: literal
end
