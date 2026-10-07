defmodule Gust.DAG.Source.S3 do
  @compile {:no_warn_undefined,
            [
              {ExAws.S3, :list_objects_v2, 2},
              {ExAws, :request, 2},
              {ExAws.S3, :get_object, 2}
            ]}

  @moduledoc """
  DAG source that loads definitions from an AWS S3 bucket.

  Requires the ex_aws and ex_aws_s3 libraries to be installed.
  Changes are detected via polling.

  Configuration:
    - `:bucket`             — S3 bucket name (required)
    - `:prefix`             — Path prefix within bucket (default: "")
    - `:region`             — AWS region (default: "us-east-1")
    - `:poll_seconds`       — Polling interval in seconds (default: 30)
    - `:access_key_id`      — AWS access key (optional, uses SDK credential chain if not provided)
    - `:secret_access_key`  — AWS secret key (optional, uses SDK credential chain if not provided)

  AWS credentials are resolved in the following order:
    1. If `:access_key_id` and `:secret_access_key` are provided in config, use them
    2. Otherwise, use the standard AWS SDK credential chain:
       - Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
       - AWS credentials file (~/.aws/credentials)
       - IAM role (when running on EC2 or ECS)

  Example configuration:
  ```elixir
  config :gust,
    dag_sources: [
      {"s3-main",
      type:   S3,
      bucket: "my-dags",
      prefix: "workflows/",
      region: "us-west-2"}
    ]
  ```
  """
  @name __MODULE__ |> Module.split() |> List.last()

  @behaviour Gust.DAG.Source

  alias Gust.DAG.Adapter
  alias Gust.DAG.Parser
  alias Gust.DAG.Source.Polling

  # This avoids compiler warnings about non-exported load/0
  @impl true
  def load, do: load(nil)

  @impl true
  def load(_effective_time) do
    with {:ok, _} <- verify_ex_aws_available(),
         {:ok, objects} <- list_s3_objects() do
      dags = Enum.flat_map(objects, &parse_s3_object/1)

      # Partition DAGs into success and error lists, unwrapping the tuples
      {success, error} =
        Enum.reduce(dags, {[], []}, fn
          {name, {:ok, value}}, {success, error} -> {[{name, value} | success], error}
          {name, {:error, reason}}, {success, error} -> {success, [{name, reason} | error]}
        end)

      %{success: success |> Enum.reverse(), error: error |> Enum.reverse()}
    else
      {:error, reason} ->
        {:error, inspect(reason)}
    end
  rescue
    e -> {:error, inspect(e)}
  end

  @impl true
  def monitor(loader_pid, _config \\ %{}) do
    poll_interval_ms = poll_seconds() * 1_000

    Polling.start_link(loader_pid, &load/0, poll_interval_ms)
  end

  @impl true
  def name, do: @name

  # Private functions

  defp verify_ex_aws_available do
    if Code.ensure_loaded?(ExAws) and Code.ensure_loaded?(ExAws.S3) do
      {:ok, true}
    else
      {:error, "ex_aws and ex_aws_s3 are not installed. Add them to your mix.exs dependencies."}
    end
  end

  defp list_s3_objects do
    bucket = get_bucket()

    if is_nil(bucket) do
      {:error, "S3 DAG source: bucket '#{bucket}' not configured"}
    else
      prefix = get_prefix()

      bucket
      |> ExAws.S3.list_objects_v2(prefix: prefix)
      |> ExAws.request(aws_config())
      |> case do
        {:ok, %{"Contents" => contents}} when is_list(contents) ->
          contents
          |> Enum.filter(&dag_file?/1)
          |> then(&{:ok, &1})

        {:ok, %{"Contents" => nil}} ->
          {:ok, []}

        {:ok, %{}} ->
          {:ok, []}

        {:error, reason} ->
          {:error, "Failed to list S3 objects: #{inspect(reason)}"}
      end
    end
  rescue
    e -> {:error, "Error listing S3 objects: #{inspect(e)}"}
  end

  defp dag_file?(object) do
    key = object["Key"]
    extension = Path.extname(key)
    Adapter.parser_for_extension(extension) != nil
  end

  defp parse_s3_object(object) do
    key = object["Key"]
    dag_name = s3_key_to_dag_name(key)

    case download_s3_object(key) do
      {:ok, content} ->
        case parse_dag_content(content) do
          {:ok, definition} ->
            {dag_name, {:ok, definition}}

          {:error, reason} ->
            {dag_name, {:error, "Failed to parse DAG from S3 key #{key}: #{inspect(reason)}"}}
        end

      {:error, reason} ->
        {dag_name, {:error, "Failed to download DAG from S3 key #{key}: #{inspect(reason)}"}}
    end
  rescue
    e ->
      dag_name = s3_key_to_dag_name(object["Key"])
      {dag_name, {:error, "Error processing S3 object with key #{object["Key"]}: #{inspect(e)}"}}
  end

  defp download_s3_object(key) do
    bucket = get_bucket()

    bucket
    |> ExAws.S3.get_object(key)
    |> ExAws.request(aws_config())
    |> case do
      {:ok, %{"Body" => body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp parse_dag_content(content) when is_binary(content) do
    # Create a temporary file for the DAG content
    temp_dir = System.tmp_dir!()
    timestamp = System.monotonic_time(:microsecond)
    temp_file = Path.join(temp_dir, "gust-dag-s3-#{timestamp}.tmp")

    try do
      File.write!(temp_file, content)

      # Try to detect format from content or use a sensible parser
      extension = detect_extension(content)
      parser_module = Adapter.parser_for_extension(extension)

      if parser_module do
        Parser.parse(parser_module, temp_file)
      else
        {:error, "Could not detect DAG format"}
      end
    rescue
      e -> {:error, e}
    after
      File.rm(temp_file)
    end
  end

  defp parse_dag_content(_), do: {:error, "Invalid content type"}

  defp detect_extension(content) do
    # Try to detect if it's Elixir or YAML
    content_str = if is_binary(content), do: content, else: ""

    cond do
      String.contains?(content_str, ["defmodule", "def ", "use Gust"]) -> ".ex"
      String.contains?(content_str, ["---", "nodes:", "edges:"]) -> ".yml"
      String.contains?(content_str, [": ", "- "]) -> ".yml"
      # Default to Elixir
      true -> ".ex"
    end
  end

  defp s3_key_to_dag_name(key) do
    prefix = get_prefix()

    # Remove prefix if present
    dag_path =
      if prefix != "" and String.starts_with?(key, prefix) do
        String.slice(key, String.length(prefix)..-1)
      else
        key
      end

    # Remove extension
    Path.rootname(dag_path)
  end

  defp get_bucket do
    case Gust.DAG.Source.config()
         |> Keyword.fetch(:bucket) do
      {:ok, bucket} -> bucket
      :error -> nil
    end
  end

  defp get_prefix do
    Gust.DAG.Source.config()
    |> Keyword.get(:prefix, "")
  end

  defp get_region do
    Gust.DAG.Source.config()
    |> Keyword.get(:region, "us-east-1")
  end

  defp poll_seconds do
    Gust.DAG.Source.config()
    |> Keyword.get(:poll_seconds, 30)
  end

  defp aws_config do
    config = Gust.DAG.Source.config()
    region = get_region()

    base_config = [region: region]

    # Add credentials if explicitly provided in config
    base_config =
      case {Keyword.get(config, :access_key_id), Keyword.get(config, :secret_access_key)} do
        {key_id, secret_key} when is_binary(key_id) and is_binary(secret_key) ->
          base_config ++ [access_key_id: key_id, secret_access_key: secret_key]

        _ ->
          # Use SDK credential chain
          base_config
      end

    base_config
  end
end
