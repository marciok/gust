defmodule Gust.Encrypted.Binary do
  @moduledoc false
  use Cloak.Ecto.Binary, vault: Gust.Vault
end
