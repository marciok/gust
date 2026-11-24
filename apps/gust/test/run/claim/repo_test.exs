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

      assert is_nil(Claim.renew_run(run.id, Ecto.UUID.generate()))
    end

    test "claim token is found" do
      dag = dag_fixture(%{name: "hungry_for_renew"})
      run = run_fixture(%{dag_id: dag.id, status: :running, claim_token: Ecto.UUID.generate()})
      run_id = run.id

      now = DateTime.utc_now()
      lease_seconds = 15

      assert %Flows.Run{id: ^run_id, claim_expires_at: new_expiration_date} =
               Claim.renew_run(run.id, run.claim_token)

      assert DateTime.diff(now, new_expiration_date) in [-(lease_seconds + 1), -lease_seconds]
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

      assert %Flows.Run{
               id: ^run_id,
               status: :starting,
               claim_token: token,
               claimed_by: ^node,
               claim_expires_at: expiration_date
             } = Claim.next_run()

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

      assert %Flows.Run{
               id: ^run_id,
               status: :starting,
               claim_token: token,
               claimed_by: ^node,
               claim_expires_at: expiration_date
             } = Claim.next_run()

      refute is_nil(token)
      assert DateTime.diff(expiration_date, expire_at) == 0
    end

    test "does not claim enqueued runs for disabled dags", %{
      node: node,
      dag: dag
    } do
      disabled_dag = dag_fixture(%{name: "disabled_for_claim", enabled: false})
      _disabled_run = run_fixture(%{dag_id: disabled_dag.id, status: :enqueued})
      enabled_run = run_fixture(%{dag_id: dag.id, status: :enqueued})
      enabled_run_id = enabled_run.id

      assert %Flows.Run{
               id: ^enabled_run_id,
               status: :starting,
               claimed_by: ^node
             } = Claim.next_run()
    end

    test "does not reclaim expired running runs for disabled dags", %{dag: dag} do
      now = DateTime.utc_now()
      expired = DateTime.add(now, -10)

      disabled_dag = dag_fixture(%{name: "disabled_expired_running", enabled: false})

      _disabled_run =
        run_fixture(%{
          dag_id: disabled_dag.id,
          status: :running,
          claim_expires_at: expired
        })

      enabled_run = run_fixture(%{dag_id: dag.id, status: :enqueued})
      enabled_run_id = enabled_run.id

      assert %Flows.Run{id: ^enabled_run_id} = Claim.next_run()
    end

    test "reclaims a starting run after its lease expires", %{dag: dag} do
      expired = DateTime.add(DateTime.utc_now(), -10)

      run =
        run_fixture(%{
          dag_id: dag.id,
          status: :starting,
          claim_expires_at: expired
        })

      assert %Flows.Run{id: run_id, status: :starting, claim_token: token} = Claim.next_run()
      assert run_id == run.id
      refute is_nil(token)
    end

    test "nothing to claim" do
      assert is_nil(Claim.next_run())
    end
  end

  describe "next_run/1 with sequential dags" do
    setup do
      dag = dag_fixture(%{name: "sequential_dag"})
      %{seq: dag, seq_ids: [dag.id]}
    end

    test "doesn't claim a queued run while the dag has an active run", %{seq: seq, seq_ids: ids} do
      for status <- [:starting, :running, :waiting] do
        _active = run_fixture(%{dag_id: seq.id, status: status, claim_expires_at: later()})
        _queued = run_fixture(%{dag_id: seq.id, status: :enqueued})

        assert nil == Claim.next_run(ids)

        Repo.delete_all(from r in Flows.Run, where: r.dag_id == ^seq.id)
      end
    end

    test "claims the next run after the active one succeeds or fails", %{
      seq: seq,
      seq_ids: ids
    } do
      for finished <- [:succeeded, :failed] do
        active = run_fixture(%{dag_id: seq.id, status: :running, claim_expires_at: later()})
        queued = run_fixture(%{dag_id: seq.id, status: :enqueued})

        assert nil == Claim.next_run(ids)

        Flows.update_run_status(active, finished)
        queued_id = queued.id
        assert %Flows.Run{id: ^queued_id, status: :starting} = Claim.next_run(ids)

        Repo.delete_all(from r in Flows.Run, where: r.dag_id == ^seq.id)
      end
    end

    test "claims queued runs one at a time, oldest first", %{seq: seq, seq_ids: ids} do
      [first, second, third] =
        Enum.map(1..3, fn _ -> run_fixture(%{dag_id: seq.id, status: :enqueued}) end)

      for run <- [first, second, third] do
        run_id = run.id
        assert %Flows.Run{id: ^run_id} = claimed = Claim.next_run(ids)
        assert nil == Claim.next_run(ids)
        Flows.update_run_status(claimed, :succeeded)
      end

      assert nil == Claim.next_run(ids)
    end

    test "still claims runs of other dags", %{dag: dag, seq: seq, seq_ids: ids} do
      _active = run_fixture(%{dag_id: seq.id, status: :running, claim_expires_at: later()})
      _blocked = run_fixture(%{dag_id: seq.id, status: :enqueued})
      other = run_fixture(%{dag_id: dag.id, status: :enqueued})
      other_id = other.id

      assert %Flows.Run{id: ^other_id} = Claim.next_run(ids)
    end

    test "reclaims an expired active run and keeps the queue blocked", %{
      seq: seq,
      seq_ids: ids
    } do
      expired = DateTime.add(DateTime.utc_now(), -10)
      active = run_fixture(%{dag_id: seq.id, status: :running, claim_expires_at: expired})
      _queued = run_fixture(%{dag_id: seq.id, status: :enqueued})
      active_id = active.id

      assert %Flows.Run{id: ^active_id, status: :starting} = Claim.next_run(ids)
      assert nil == Claim.next_run(ids)
    end

    test "parallel dags still run queued runs side by side", %{seq: seq} do
      _active = run_fixture(%{dag_id: seq.id, status: :running, claim_expires_at: later()})
      queued = run_fixture(%{dag_id: seq.id, status: :enqueued})
      queued_id = queued.id

      assert %Flows.Run{id: ^queued_id} = Claim.next_run([])
    end
  end

  defp later, do: DateTime.add(DateTime.utc_now(), 60)
end
