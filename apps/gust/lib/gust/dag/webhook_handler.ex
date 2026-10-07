defmodule Gust.DAG.WebhookHandler do
  @moduledoc """
  Validates and processes Git webhook payloads.

  Supports GitHub, GitLab, and Gitea webhooks with HMAC signature validation.
  """

  @doc """
  Validates a webhook signature using HMAC-SHA256.

  ## Parameters
    - `payload` - Raw request body as string
    - `signature` - Signature from webhook header
    - `secret` - Shared secret for HMAC validation
    - `algorithm` - Hash algorithm (default: :sha256)

  ## Returns
    - `true` if signature is valid
    - `false` otherwise
  """
  def validate_signature(payload, signature, secret, algorithm \\ :sha256) do
    case compute_signature(payload, secret, algorithm) do
      computed -> secure_compare(computed, signature)
    end
  rescue
    _ -> false
  end

  @doc """
  Computes HMAC signature for a payload.

  ## Parameters
    - `payload` - Raw request body as string
    - `secret` - Shared secret
    - `algorithm` - Hash algorithm (default: :sha256)

  ## Returns
    - Hex-encoded signature string
  """
  def compute_signature(payload, secret, algorithm \\ :sha256) do
    :crypto.mac(:hmac, algorithm, secret, payload)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Parses a GitHub push webhook payload.

  Extracts changed DAG files from the commit list.

  ## Parameters
    - `payload` - Parsed JSON payload (map)

  ## Returns
    - `{:ok, %{changed_files: [...], branch: "...", repository: "..."}}`
    - `{:error, reason}` if parsing fails
  """
  def parse_github_payload(payload) when is_map(payload) do
    with {:ok, ref} <- get_in(payload, ["ref"]) |> to_result(),
         {:ok, commits} <- get_in(payload, ["commits"]) |> to_list_result(),
         {:ok, repo} <- get_in(payload, ["repository", "full_name"]) |> to_result() do
      branch = extract_branch(ref)
      changed_files = extract_files_from_commits(commits)

      {:ok,
       %{
         changed_files: changed_files,
         branch: branch,
         repository: repo,
         platform: :github
       }}
    else
      :error -> {:error, "Invalid GitHub payload structure"}
    end
  end

  def parse_github_payload(_), do: {:error, "Payload must be a map"}

  @doc """
  Parses a GitLab push webhook payload.

  Extracts changed DAG files from the commit list.

  ## Parameters
    - `payload` - Parsed JSON payload (map)

  ## Returns
    - `{:ok, %{changed_files: [...], branch: "...", repository: "..."}}`
    - `{:error, reason}` if parsing fails
  """
  def parse_gitlab_payload(payload) when is_map(payload) do
    with {:ok, ref} <- get_in(payload, ["ref"]) |> to_result(),
         {:ok, commits} <- get_in(payload, ["commits"]) |> to_list_result(),
         {:ok, repo} <- get_in(payload, ["project", "path_with_namespace"]) |> to_result() do
      branch = extract_branch(ref)
      changed_files = extract_files_from_commits(commits)

      {:ok,
       %{
         changed_files: changed_files,
         branch: branch,
         repository: repo,
         platform: :gitlab
       }}
    else
      :error -> {:error, "Invalid GitLab payload structure"}
    end
  end

  def parse_gitlab_payload(_), do: {:error, "Payload must be a map"}

  @doc """
  Parses a Gitea push webhook payload.

  Extracts changed DAG files from the commit list.

  ## Parameters
    - `payload` - Parsed JSON payload (map)

  ## Returns
    - `{:ok, %{changed_files: [...], branch: "...", repository: "..."}}`
    - `{:error, reason}` if parsing fails
  """
  def parse_gitea_payload(payload) when is_map(payload) do
    with {:ok, ref} <- get_in(payload, ["ref"]) |> to_result(),
         {:ok, commits} <- get_in(payload, ["commits"]) |> to_list_result(),
         {:ok, repo} <- get_in(payload, ["repository", "full_name"]) |> to_result() do
      branch = extract_branch(ref)
      changed_files = extract_files_from_commits(commits)

      {:ok,
       %{
         changed_files: changed_files,
         branch: branch,
         repository: repo,
         platform: :gitea
       }}
    else
      :error -> {:error, "Invalid Gitea payload structure"}
    end
  end

  def parse_gitea_payload(_), do: {:error, "Payload must be a map"}

  @doc """
  Filters changed files to only include DAG files.

  DAG files are identified by their extensions: .ex, .yml, .yaml

  ## Parameters
    - `changed_files` - List of file paths
    - `dag_folder_prefix` - Optional folder prefix to filter by (e.g., "dags/")

  ## Returns
    - List of DAG files that changed
  """
  def filter_dag_files(changed_files, dag_folder_prefix \\ nil) do
    changed_files
    |> Enum.filter(&dag_file?/1)
    |> maybe_filter_by_prefix(dag_folder_prefix)
  end

  @doc """
  Determines if a file should be reloaded based on extension.
  """
  def dag_file?(path) when is_binary(path) do
    ext = Path.extname(path)
    ext in [".ex", ".yml", ".yaml"]
  end

  def dag_file?(_), do: false

  # Private helpers

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    # Constant-time comparison to prevent timing attacks
    byte_size(a) == byte_size(b) && :crypto.hash_equals(a, b)
  end

  defp secure_compare(_, _), do: false

  defp extract_branch("refs/heads/" <> branch), do: branch
  defp extract_branch("refs/tags/" <> tag), do: tag
  defp extract_branch(ref), do: ref

  defp extract_files_from_commits(commits) when is_list(commits) do
    commits
    |> Enum.flat_map(fn commit ->
      if is_map(commit) do
        added = Map.get(commit, "added", [])
        modified = Map.get(commit, "modified", [])
        removed = Map.get(commit, "removed", [])
        added ++ modified ++ removed
      else
        []
      end
    end)
    |> Enum.uniq()
  end

  defp maybe_filter_by_prefix(files, nil), do: files

  defp maybe_filter_by_prefix(files, prefix) when is_binary(prefix) do
    Enum.filter(files, &String.starts_with?(&1, prefix))
  end

  defp to_result(value) when value != nil, do: {:ok, value}
  defp to_result(_), do: :error

  defp to_list_result(value) when is_list(value), do: {:ok, value}
  defp to_list_result(_), do: :error
end
