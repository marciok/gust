defmodule Gust.DAG.Source.MonitorState do
  @moduledoc """
  Persists per-source monitor lifecycle state in the database.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Gust.Repo

  @type status :: :running | :paused | :stopped
  @type t :: %__MODULE__{id: String.t(), source_type: String.t(), status: status()}

  @primary_key {:id, :string, autogenerate: false}
  schema "gust_source_monitor_states" do
    field :source_type, :string
    field :status, Ecto.Enum, values: [:running, :paused, :stopped], default: :running

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(monitor_state, attrs) do
    monitor_state
    |> cast(attrs, [:id, :source_type, :status])
    |> validate_required([:id, :source_type, :status])
    |> validate_inclusion(:status, [:running, :paused, :stopped])
  end

  @doc """
  Save the monitor state for the given source id and source type.
  """
  @spec save(term(), module() | String.t(), status()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def save(id, source_type, status) do
    attrs = %{
      id: to_string(id),
      source_type: normalize_source_type(source_type),
      status: normalize_status(status)
    }

    record = Repo.get(__MODULE__, attrs.id)

    case record do
      nil -> %__MODULE__{} |> changeset(attrs) |> Repo.insert()
      _record -> record |> changeset(attrs) |> Repo.update()
    end
  end

  def save(%{id: id, source_type: source_type, status: status}) do
    save(id, source_type, status)
  end

  @doc """
  Read the last persisted status for the given source id and source type.
  """
  @spec read(term(), module() | String.t()) :: status()
  def read(id, source_type) do
    case Repo.get_by(__MODULE__,
           id: to_string(id),
           source_type: normalize_source_type(source_type)
         ) do
      nil -> :running
      %__MODULE__{status: status} -> status
    end
  end

  @doc false
  @spec read_all() :: [t()]
  def read_all do
    Repo.all(__MODULE__)
  end

  defp normalize_source_type(source_type) do
    source_type
    |> to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp normalize_status(status) when status in [:running, :paused, :stopped], do: status

  defp normalize_status(status) when is_binary(status) do
    case String.downcase(status) do
      "running" -> :running
      "paused" -> :paused
      "stopped" -> :stopped
      other -> raise ArgumentError, "Unsupported monitor status: #{inspect(other)}"
    end
  end

  defp normalize_status(other) do
    raise ArgumentError, "Unsupported monitor status: #{inspect(other)}"
  end
end
