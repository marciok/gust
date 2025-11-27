defmodule Gust.Vault do
  @moduledoc false
  use Cloak.Vault, otp_app: :gust

  @impl GenServer
  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: decode_env!()}
      )

    {:ok, config}
  end

  defp decode_env! do
    Application.get_env(:gust, :b64_secrets_cloak_key) |> Base.decode64!()
  end
end
