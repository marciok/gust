defmodule Run.Claim.RepoTest do
  alias Gust.Flows
  use Gust.DataCase
  import Gust.FlowsFixtures

  alias Gust.Run.Claim.Repo, as: Claim

  setup do
    node = to_string(Node.self())
    now = DateTime.utc_now()
    lease_seconds = 15
    expire_at = DateTime.add(now, lease_seconds)
    later_expiration = DateTime.add(now, lease_seconds + 10)

    dag = dag_fixture(%{name: "hungry_for_claim"})
    _created_run = run_fixture(%{dag_id: dag.id, status: :created})
    _failed_run = run_fixture(%{dag_id: dag.id, status: :failed})
    _succeeded_run = run_fixture(%{dag_id: dag.id, status: :succeeded})

    %{expire_at: expire_at, node: node, later_expiration: later_expiration, dag: dag}
  end

  describe "renew_run/2" do
    test "claim token is not found" do
      dag = dag_fixture(%{name: "hungry_for_renew"})
      run = run_fixture(%{dag_id: dag.id, status: :running, claim_token: Ecto.UUID.generate()})

      assert {:ok, nil} = Claim.renew_run(run.id, Ecto.UUID.generate())
    end

    test "claim token is found" do
      dag = dag_fixture(%{name: "hungry_for_renew"})
      run = run_fixture(%{dag_id: dag.id, status: :running, claim_token: Ecto.UUID.generate()})
      run_id = run.id

      now = DateTime.utc_now()
      lease_seconds = 15

      assert {:ok, %Flows.Run{id: ^run_id, claim_expires_at: new_expiration_date}} =
               Claim.renew_run(run.id, run.claim_token)

      assert DateTime.diff(now, new_expiration_date) == -lease_seconds
    end
  end

  describe "next_run/0" do
    test "claim enqueued run", %{
      node: node,
      later_expiration: later_expiration,
      dag: dag,
      expire_at: expire_at
    } do
      _running_and_claimed =
        run_fixture(%{dag_id: dag.id, status: :running, claim_expires_at: later_expiration})

      run = run_fixture(%{dag_id: dag.id, status: :enqueued})
      _second_run = run_fixture(%{dag_id: dag.id, status: :enqueued})

      run_id = run.id

      assert {:ok,
              %Flows.Run{
                id: ^run_id,
                status: :running,
                claim_token: token,
                claimed_by: ^node,
                claim_expires_at: expiration_date
              }} = Claim.next_run()

      refute is_nil(token)
      assert DateTime.diff(expiration_date, expire_at) == 0
    end

    test "claim expired running", %{
      node: node,
      dag: dag,
      expire_at: expire_at
    } do
      now = DateTime.utc_now()
      expired = DateTime.add(now, -10)

      running_and_expired =
        run_fixture(%{dag_id: dag.id, status: :running, claim_expires_at: expired})

      run_id = running_and_expired.id

      assert {:ok,
              %Flows.Run{
                id: ^run_id,
                status: :running,
                claim_token: token,
                claimed_by: ^node,
                claim_expires_at: expiration_date
              }} = Claim.next_run()

      refute is_nil(token)
      assert DateTime.diff(expiration_date, expire_at) == 0
    end

    test "nothing to claim" do
      assert {:ok, nil} = Claim.next_run()
    end
  end
end
