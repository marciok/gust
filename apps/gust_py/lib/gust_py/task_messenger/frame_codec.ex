defmodule GustPy.TaskMessenger.FrameCodec do
  @moduledoc false

  def encode(payload) when is_binary(payload) do
    <<byte_size(payload)::unsigned-big-integer-size(32)>> <> payload
  end

  def decode(buffer, new_bytes) do
    take_frames(buffer <> new_bytes, [])
  end

  defp take_frames(<<len::unsigned-big-integer-size(32), rest::binary>>, acc)
       when byte_size(rest) >= len do
    <<frame::binary-size(len), remaining::binary>> = rest
    take_frames(remaining, [frame | acc])
  end

  defp take_frames(remaining, acc), do: {Enum.reverse(acc), remaining}
end
