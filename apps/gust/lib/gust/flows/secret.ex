defmodule Gust.Flows.Secret do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Jason.Encoder, only: [:id, :name, :value_type, :inserted_at, :updated_at]}
  schema "secrets" do
    field :name, :string
    field :value, Gust.Encrypted.Binary, redact: true
    field :value_type, Ecto.Enum, values: [:string, :json]

    timestamps()
  end

  @doc false
  def changeset(secret, attrs) do
    secret
    |> cast(attrs, [:name, :value, :value_type])
    |> validate_required([:name, :value, :value_type])
    |> validate_format(:name, ~r/^[A-Z0-9_]+$/, message: "must be uppercase with underscores")
    |> unique_constraint(:name)
    |> validate_json_if_needed()
  end

  defp validate_json_if_needed(changeset) do
    case get_field(changeset, :value_type) do
      :json ->
        value = get_field(changeset, :value)
        validate_json(value, changeset)

      _ ->
        changeset
    end
  end

  defp validate_json(nil, changeset) do
    add_error(changeset, :value, "it cannot be empty")
  end

  defp validate_json(value, changeset) when is_bitstring(value) do
    case Jason.decode(value) do
      {:ok, _decoded} -> changeset
      {:error, _} -> add_error(changeset, :value, "must be valid JSON")
    end
  end
end
