defmodule Gust.DAG.WebhookHandlerTest do
  use ExUnit.Case, async: true

  alias Gust.DAG.WebhookHandler

  describe "validate_signature/4" do
    test "returns true for valid HMAC-SHA256 signature" do
      payload = "test payload"
      secret = "my-secret"

      signature = WebhookHandler.compute_signature(payload, secret)

      assert WebhookHandler.validate_signature(payload, signature, secret)
    end

    test "returns false for invalid signature" do
      payload = "test payload"
      secret = "my-secret"

      assert !WebhookHandler.validate_signature(payload, "invalid-sig", secret)
    end

    test "returns false for mismatched secret" do
      payload = "test payload"
      secret = "my-secret"

      signature = WebhookHandler.compute_signature(payload, secret)

      assert !WebhookHandler.validate_signature(payload, signature, "wrong-secret")
    end

    test "returns false for tampered payload" do
      payload = "test payload"
      secret = "my-secret"

      signature = WebhookHandler.compute_signature(payload, secret)

      assert !WebhookHandler.validate_signature("tampered payload", signature, secret)
    end
  end

  describe "compute_signature/3" do
    test "returns consistent signature for same payload and secret" do
      payload = "test payload"
      secret = "my-secret"

      sig1 = WebhookHandler.compute_signature(payload, secret)
      sig2 = WebhookHandler.compute_signature(payload, secret)

      assert sig1 == sig2
    end

    test "returns different signature for different payload" do
      secret = "my-secret"

      sig1 = WebhookHandler.compute_signature("payload1", secret)
      sig2 = WebhookHandler.compute_signature("payload2", secret)

      assert sig1 != sig2
    end
  end

  describe "parse_github_payload/1" do
    test "parses valid GitHub push payload" do
      payload = %{
        "ref" => "refs/heads/main",
        "repository" => %{"full_name" => "company/dags"},
        "commits" => [
          %{
            "added" => ["dags/workflow1.ex"],
            "modified" => ["dags/workflow2.ex"],
            "removed" => []
          }
        ]
      }

      assert {:ok,
              %{
                changed_files: ["dags/workflow1.ex", "dags/workflow2.ex"],
                branch: "main",
                repository: "company/dags",
                platform: :github
              }} = WebhookHandler.parse_github_payload(payload)
    end

    test "handles missing optional fields" do
      payload = %{
        "ref" => "refs/heads/main",
        "repository" => %{"full_name" => "company/dags"},
        "commits" => [
          %{
            "added" => ["new.ex"]
          }
        ]
      }

      assert {:ok, result} = WebhookHandler.parse_github_payload(payload)
      assert result.changed_files == ["new.ex"]
    end

    test "returns error for invalid payload" do
      assert {:error, _} = WebhookHandler.parse_github_payload(%{"invalid" => "payload"})
    end

    test "returns error for non-map payload" do
      assert {:error, _} = WebhookHandler.parse_github_payload("not a map")
    end
  end

  describe "parse_gitlab_payload/1" do
    test "parses valid GitLab push payload" do
      payload = %{
        "ref" => "refs/heads/main",
        "project" => %{"path_with_namespace" => "company/dags"},
        "commits" => [
          %{
            "added" => ["dags/job.ex"],
            "modified" => [],
            "removed" => []
          }
        ]
      }

      assert {:ok,
              %{
                changed_files: ["dags/job.ex"],
                branch: "main",
                repository: "company/dags",
                platform: :gitlab
              }} = WebhookHandler.parse_gitlab_payload(payload)
    end

    test "returns error for invalid payload" do
      assert {:error, _} = WebhookHandler.parse_gitlab_payload(%{"invalid" => "payload"})
    end
  end

  describe "parse_gitea_payload/1" do
    test "parses valid Gitea push payload" do
      payload = %{
        "ref" => "refs/heads/main",
        "repository" => %{"full_name" => "company/dags"},
        "commits" => [
          %{
            "added" => ["dags/sync.ex"],
            "modified" => [],
            "removed" => []
          }
        ]
      }

      assert {:ok,
              %{
                changed_files: ["dags/sync.ex"],
                branch: "main",
                repository: "company/dags",
                platform: :gitea
              }} = WebhookHandler.parse_gitea_payload(payload)
    end

    test "returns error for invalid payload" do
      assert {:error, _} = WebhookHandler.parse_gitea_payload(%{"invalid" => "payload"})
    end
  end

  describe "filter_dag_files/2" do
    test "filters files by DAG extensions" do
      files = [
        "dags/workflow1.ex",
        "dags/workflow2.yml",
        "dags/workflow3.yaml",
        "dags/README.md",
        "dags/config.json",
        "dags/script.sh"
      ]

      dag_files = WebhookHandler.filter_dag_files(files)

      assert Enum.sort(dag_files) ==
               Enum.sort(["dags/workflow1.ex", "dags/workflow2.yml", "dags/workflow3.yaml"])
    end

    test "filters by prefix when provided" do
      files = [
        "workflows/job1.ex",
        "workflows/job2.yml",
        "docs/readme.md",
        "dags/other.ex"
      ]

      dag_files = WebhookHandler.filter_dag_files(files, "workflows/")

      assert dag_files == ["workflows/job1.ex", "workflows/job2.yml"]
    end

    test "returns empty list when no DAG files" do
      files = ["README.md", "config.json", "script.sh"]

      assert WebhookHandler.filter_dag_files(files) == []
    end
  end

  describe "dag_file?/1" do
    test "returns true for .ex files" do
      assert WebhookHandler.dag_file?("workflow.ex")
      assert WebhookHandler.dag_file?("dags/workflow.ex")
    end

    test "returns true for .yml files" do
      assert WebhookHandler.dag_file?("workflow.yml")
      assert WebhookHandler.dag_file?("dags/workflow.yml")
    end

    test "returns true for .yaml files" do
      assert WebhookHandler.dag_file?("workflow.yaml")
      assert WebhookHandler.dag_file?("dags/workflow.yaml")
    end

    test "returns false for other extensions" do
      assert !WebhookHandler.dag_file?("README.md")
      assert !WebhookHandler.dag_file?("config.json")
      assert !WebhookHandler.dag_file?("script.sh")
    end
  end
end
