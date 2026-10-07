defmodule GustWeb.DagWebhookControllerTest do
  use GustWeb.ConnCase, async: false

  import Gust.ApplicationEnvHelpers
  alias Gust.DAG.WebhookHandler

  setup :init_dag_source

  setup do
    # Create a mock loader PID for testing.
    # It is registered under the same name the controller consults, but we clean it up
    # defensively because the whole suite shares process names globally.
    {:ok, loader_pid} = Agent.start_link(fn -> [] end)

    try do
      Process.unregister(GustWeb.DAGLoaderMock)
    rescue
      ArgumentError -> :ok
    end

    true = Process.register(loader_pid, GustWeb.DAGLoaderMock)

    on_exit(fn ->
      try do
        Process.unregister(GustWeb.DAGLoaderMock)
      rescue
        ArgumentError -> :ok
      end

      if Process.alive?(loader_pid) do
        try do
          Agent.stop(loader_pid)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    {:ok, loader_pid: loader_pid}
  end

  describe "POST /api/webhooks/github" do
    test "accepts valid GitHub webhook when signed raw JSON contains extra whitespace" do
      secret = "test-secret"

      put_git_webhook_source(webhook_secret: secret)

      payload =
        """
        {
          "ref": "refs/heads/main",
          "repository": { "full_name": "company/dags" },
          "commits": [
            {
              "added": ["dags/workflow.ex"],
              "modified": [],
              "removed": []
            }
          ]
        }
        """

      signature = WebhookHandler.compute_signature(payload, secret)

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", "sha256=#{signature}")
        |> post("/api/webhooks/github", payload)

      assert %{
               "status" => "ok",
               "message" => "Webhook github processed"
             } = json_response(conn, 200)
    end

    test "accepts valid GitHub webhook with correct signature" do
      secret = "test-secret"

      put_git_webhook_source(webhook_secret: secret)

      payload =
        Glazer.JSON.encode!(%{
          "ref" => "refs/heads/main",
          "repository" => %{"full_name" => "company/dags"},
          "commits" => [
            %{
              "added" => ["dags/workflow.ex"],
              "modified" => [],
              "removed" => []
            }
          ]
        })

      signature = WebhookHandler.compute_signature(payload, secret)

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", "sha256=#{signature}")
        |> post("/api/webhooks/github", payload)

      assert %{
               "status" => "ok",
               "message" => "Webhook github processed"
             } = json_response(conn, 200)
    end

    test "rejects GitHub webhook with invalid signature" do
      put_git_webhook_source(webhook_secret: "test-secret")

      payload =
        Glazer.JSON.encode!(%{
          "ref" => "refs/heads/main",
          "repository" => %{"full_name" => "company/dags"},
          "commits" => []
        })

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", "sha256=invalid")
        |> post("/api/webhooks/github", payload)

      assert %{"message" => "Invalid signature", "status" => "error"} = json_response(conn, 400)
    end

    test "rejects GitHub webhook with missing signature header" do
      payload = Glazer.JSON.encode!(%{})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/github", payload)

      assert %{"message" => "Missing X-Hub-Signature-256 header", "status" => "error"} =
               json_response(conn, 400)
    end

    test "rejects GitHub webhook with malformed signature format" do
      put_git_webhook_source(webhook_secret: "test-secret")

      payload = Glazer.JSON.encode!(%{})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", "invalid-format")
        |> post("/api/webhooks/github", payload)

      assert %{"message" => "Invalid signature format", "status" => "error"} =
               json_response(conn, 400)
    end
  end

  describe "POST /api/webhooks/gitlab" do
    test "accepts valid GitLab webhook with correct token" do
      secret = "gitlab-secret-token"

      put_git_webhook_source(webhook_secret: secret)

      payload =
        Glazer.JSON.encode!(%{
          "ref" => "refs/heads/main",
          "project" => %{"path_with_namespace" => "company/dags"},
          "commits" => [
            %{
              "added" => ["dags/job.ex"],
              "modified" => [],
              "removed" => []
            }
          ]
        })

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-gitlab-token", secret)
        |> post("/api/webhooks/gitlab", payload)

      assert %{"message" => "Webhook gitlab processed", "status" => "ok"} =
               json_response(conn, 200)
    end

    test "rejects GitLab webhook with invalid token" do
      put_git_webhook_source(webhook_secret: "correct-token")

      payload = Glazer.JSON.encode!(%{})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-gitlab-token", "wrong-token")
        |> post("/api/webhooks/gitlab", payload)

      assert %{"message" => "Invalid token", "status" => "error"} = json_response(conn, 400)
    end

    test "rejects GitLab webhook with missing token header" do
      payload = Glazer.JSON.encode!(%{})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/gitlab", payload)

      assert %{"message" => "Missing X-Gitlab-Token header", "status" => "error"} =
               json_response(conn, 400)
    end
  end

  describe "POST /api/webhooks/gitea" do
    test "accepts valid Gitea webhook with correct signature" do
      secret = "gitea-secret"

      put_git_webhook_source(webhook_secret: secret)

      payload =
        Glazer.JSON.encode!(%{
          "ref" => "refs/heads/main",
          "repository" => %{"full_name" => "company/dags"},
          "commits" => []
        })

      signature = WebhookHandler.compute_signature(payload, secret)

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-gitea-signature", signature)
        |> post("/api/webhooks/gitea", payload)

      assert %{"message" => "Webhook gitea processed", "status" => "ok"} =
               json_response(conn, 200)
    end

    test "rejects Gitea webhook with invalid signature" do
      put_git_webhook_source(webhook_secret: "gitea-secret")

      payload = Glazer.JSON.encode!(%{})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-gitea-signature", "invalid-sig")
        |> post("/api/webhooks/gitea", payload)

      assert %{"message" => "Invalid signature", "status" => "error"} = json_response(conn, 400)
    end
  end

  describe "POST /api/webhooks/generic" do
    test "accepts generic webhook with Bearer token" do
      secret = "generic-bearer-token"

      put_git_webhook_source(webhook_secret: secret, url: "http://localhost")

      payload = Glazer.JSON.encode!(%{"test" => "data"})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{secret}")
        |> post("/api/webhooks/generic", payload)

      assert %{"message" => "Webhook generic processed", "status" => "ok"} =
               json_response(conn, 200)
    end

    test "accepts generic webhook with query token" do
      secret = "generic-query-token"

      put_git_webhook_source(webhook_secret: secret, url: "http://localhost")

      payload = Glazer.JSON.encode!(%{"test" => "data"})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/generic?token=#{secret}", payload)

      assert %{"message" => "Webhook generic processed", "status" => "ok"} =
               json_response(conn, 200)
    end

    test "rejects generic webhook with invalid Bearer token" do
      put_git_webhook_source(webhook_secret: "correct-token")

      payload = Glazer.JSON.encode!(%{})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer wrong-token")
        |> post("/api/webhooks/generic", payload)

      assert %{"message" => "Missing or invalid Authorization header", "status" => "error"} =
               json_response(conn, 400)
    end

    test "rejects generic webhook with missing authorization" do
      payload = Glazer.JSON.encode!(%{})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/generic", payload)

      assert %{"message" => "Missing or invalid Authorization header", "status" => "error"} =
               json_response(conn, 400)
    end

    test "rejects generic webhook with invalid query token" do
      put_git_webhook_source(webhook_secret: "correct-token")

      payload = Glazer.JSON.encode!(%{})

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/webhooks/generic?token=wrong-token", payload)

      assert %{"message" => "Missing or invalid Authorization header", "status" => "error"} =
               json_response(conn, 400)
    end
  end

  describe "error handling" do
    test "returns JSON error response with error details for invalid payload" do
      secret = "test-secret"

      put_git_webhook_source(webhook_secret: secret)

      payload = Glazer.JSON.encode!(%{})
      signature = WebhookHandler.compute_signature(payload, secret)

      conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-hub-signature-256", "sha256=#{signature}")
        |> post("/api/webhooks/github", payload)

      assert json_response(conn, 400) |> Map.has_key?("status")
      assert json_response(conn, 400) |> Map.has_key?("message")
    end
  end
end
