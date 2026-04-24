defmodule GustWeb.DashboardPath do
  @moduledoc false
  @base Application.compile_env(:gust_web, :dashboard_path, "")

  defmacro sigil_g({:<<>>, _, pieces}, []) do
    base = @base
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
