defmodule GustWeb.SecretLive.Index do
  use GustWeb, :live_view

  alias Gust.Flows
  alias Gust.Flows.Secret
  alias GustWeb.LiveView.Helpers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :secrets, Flows.list_secrets())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Secrets")
    |> assign(:secret, nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    secret = Flows.get_secret!(id)
    secret = secret |> Map.put(:value, "")

    socket
    |> assign(:page_title, "Edit Secret")
    |> assign(:secret, secret)
    |> assign(:form, to_form(Flows.change_secret(secret)))
  end

  defp apply_action(socket, :new, _params) do
    secret = %Secret{}

    socket
    |> assign(:page_title, "New Secret")
    |> assign(:secret, %Secret{})
    |> assign(:form, to_form(Flows.change_secret(secret)))
  end

  @impl true
  def handle_event("validate", %{"secret" => secret_params}, socket) do
    changeset = Flows.change_secret(socket.assigns.secret, secret_params)
    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"secret" => secret_params}, socket) do
    action = socket.assigns.live_action
    save_secret(socket, action, secret_params)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    secret = Flows.get_secret!(id)
    {:ok, _} = Flows.delete_secret(secret)

    {:noreply, socket |> stream_delete(:secrets, secret)}
  end

  @impl true
  def handle_event("toggle_dag_monitor_status", _params, socket) do
    {:noreply, toggle_dag_monitor_status(socket)}
  end

  @impl true
  def handle_event("pause_dag_source", %{"value" => source_id}, socket) do
    {:noreply, Helpers.pause(socket, source_id)}
  end

  @impl true
  def handle_event("resume_dag_source", %{"value" => source_id}, socket) do
    {:noreply, Helpers.resume(socket, source_id)}
  end

  defp toggle_dag_monitor_status(socket) do
    case Process.whereis(Gust.FileMonitor.Worker) do
      nil ->
        put_flash(socket, :warning, "DAG monitor is unavailable.")

      _pid ->
        case Gust.FileMonitor.Worker.status() do
          :running ->
            Helpers.pause(socket)

          :paused ->
            Helpers.resume(socket)

          {:error, reason} ->
            put_flash(socket, :error, "DAG monitor is unavailable: #{inspect(reason)}")

          _ ->
            put_flash(socket, :warning, "DAG monitor status could not be changed.")
        end
    end
  end

  defp save_secret(socket, :new, secret_params) do
    case Flows.create_secret(secret_params) do
      {:ok, secret} ->
        socket |> apply_secret(secret, "created")
    end
  end

  defp save_secret(socket, :edit, secret_params) do
    case Flows.update_secret(socket.assigns.secret, secret_params) do
      {:ok, secret} ->
        socket |> apply_secret(secret, "updated")
    end
  end

  defp apply_secret(socket, secret, action_verb) do
    {:noreply,
     socket
     |> stream_insert(:secrets, secret)
     |> put_flash(:info, "Secret #{action_verb} successfully")
     |> push_patch(to: ~g"/secrets")}
  end
end
