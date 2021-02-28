defmodule Chat.Client do
  use GenServer
  require Logger

  def start_link(port) do
    GenServer.start_link(__MODULE__, port)
  end

  def send_message(pid, message) do
    GenServer.cast(pid, {:send_message, message})
  end

  @impl true
  def init(port) do
    port =
      case port do
        port when is_integer(port) -> port
        port when is_bitstring(port) -> String.to_integer(port)
      end

    # Because :gen_tcp.accept is blocking we have to do it in late_init
    send(self(), {:late_init, port})

    {:ok, %{socket: nil, port: port, pending_messages: []}}
  end

  @impl true
  def handle_cast({:send_message, message}, %{socket: nil} = state) do
    {:noreply, %{state | pending_messages: [message | state.pending_messages]}}
  end

  @impl true
  def handle_cast({:send_message, message}, state) do
    socket_send_message(state.socket, message)

    {:noreply, state}
  end

  @impl true
  def handle_info({:late_init, port}, state) do
    Logger.debug("Waiting for client on port: #{port}")

    {:ok, listen_socket} =
      :gen_tcp.listen(port, [:binary, packet: :line, active: true, reuseaddr: true])

    {:ok, socket} = :gen_tcp.accept(listen_socket)

    ChatWeb.Endpoint.broadcast!("room:#{port}", "connected", %{})

    state.pending_messages
    |> Enum.reverse()
    |> Enum.each(fn message -> socket_send_message(socket, message) end)

    Logger.debug("Connected to client on: #{port}")

    {:noreply, %{state | socket: socket, pending_messages: []}}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    Logger.debug("Incoming packet: #{data}")

    ChatWeb.Endpoint.broadcast!("room:#{state.port}", "new_msg", %{"message" => data})

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_closed, socket}, state) do
    Logger.debug("Connection closed for socket: #{inspect(socket)}")

    ChatWeb.Endpoint.broadcast!("room:#{state.port}", "disconnected", %{})

    {:noreply, state}
  end

  @impl true
  def handle_info({:tcp_error, socket, reason}, state) do
    Logger.debug("Connection error #{reason} for socket: #{inspect(socket)}")

    ChatWeb.Endpoint.broadcast!("room:#{state.port}", "disconnected", %{})

    {:noreply, state}
  end

  defp socket_send_message(socket, message) do
    :gen_tcp.send(socket, message <> "\r\n")
  end
end
