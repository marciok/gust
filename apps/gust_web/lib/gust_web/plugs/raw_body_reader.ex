defmodule GustWeb.Plugs.RawBodyReader do
  @moduledoc """
  Reads and caches the raw request body before parsers consume it.

  The exact bytes are stored in `conn.private[:raw_body]` so downstream
  consumers (for example webhook signature validation) can verify HMAC
  signatures against the original payload.
  """

  import Plug.Conn

  @doc false
  def read_body(conn, opts), do: do_read_body(conn, opts, [])

  defp do_read_body(conn, opts, acc) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        raw_body = IO.iodata_to_binary([acc, body])
        {:ok, raw_body, put_private(conn, :raw_body, raw_body)}

      {:more, body, conn} ->
        do_read_body(conn, opts, [acc, body])
    end
  end
end
