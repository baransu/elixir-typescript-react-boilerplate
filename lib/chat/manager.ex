defmodule Chat.Manager do
  use GenServer
  require Logger

  def start_link(ports) do
    GenServer.start_link(__MODULE__, ports, name: __MODULE__)
  end

  def get_empty_port() do
    GenServer.call(__MODULE__, :get_empty_port)
  end

  def claim(port, token) do
    GenServer.call(__MODULE__, {:claim, port, token, self()})
  end

  @impl true
  def init(ports) do
    Process.flag(:trap_exit, true)

    {:ok, %{ports: MapSet.new(ports), tokens: %{}, claims: %{}}}
  end

  @impl true
  def handle_call(:get_empty_port, _sender, state) do
    Logger.debug("Available processes: #{inspect(state.ports)}")

    {result, new_state} =
      case MapSet.to_list(state.ports) do
        [] ->
          {:error, state}

        [port | ports] ->
          token = random_string()
          tokens = Map.put(state.tokens, port, token)

          {{:ok, port, token}, %{state | tokens: tokens, ports: MapSet.new(ports)}}
      end

    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:claim, port, token, pid}, _sender, state) do
    case Map.fetch(state.tokens, port) do
      {:ok, ^token} ->
        Process.monitor(pid)

        claims = Map.put(state.claims, pid, port)
        tokens = Map.delete(state.tokens, port)

        {:reply, :ok, %{state | tokens: tokens, claims: claims}}

      _ ->
        {:reply, :error, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _msg}, state) do
    port = Map.fetch!(state.claims, pid)
    claims = Map.delete(state.claims, pid)

    ports = MapSet.put(state.ports, port)

    {:noreply, %{state | ports: ports, claims: claims}}
  end

  defp random_string(length \\ 64) do
    :crypto.strong_rand_bytes(length) |> Base.url_encode64() |> binary_part(0, length)
  end
end
