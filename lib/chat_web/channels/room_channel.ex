defmodule ChatWeb.RoomChannel do
  use Phoenix.Channel
  require Logger

  def join("room:lobby", _message, socket) do
    {:ok, port, token} = Chat.Manager.get_empty_port()

    {:ok, %{port: port, token: token}, socket}
  end

  @impl true
  def join("room:" <> port, %{"token" => token}, socket) do
    case Chat.Manager.claim(port, token) do
      :ok ->
        # We connect tcp telnet client and phoenix channel in case one of them fails we
        # stop both of them, free port. Combining it with frontend logic this will result in:
        # - if there is telnet client failure we'll return to lobby and request new port
        # - if phoenix channel exists we close telnet client and dont waste resources
        # - if phoenix channel has network problems we do the same (possible improvement would be to give some reconnect timeout and then kill telnet too)

        # Above logic is an assumption based on the task video. With full specification provided and refining contraints
        # this logic could look totaly different ie could be managed by separate static or dynamic supervisor

        # As well in this solution channel (user) is the starting point of the chat - to connect telnet we have to have
        # channel connected. Again this could be solved by starting telnet client asap and store messages in separate process
        # which would allow channel or telnet client to fail and not losing conversation history
        {:ok, client_pid} = Chat.Client.start_link(port)

        socket =
          socket
          |> assign(:port, port)
          |> assign(:client_pid, client_pid)

        {:ok, socket}

      _ ->
        {:error, %{reason: "You don't have claim on this port"}}
    end
  end

  @impl true
  def handle_in("new_msg", %{"message" => message}, socket) do
    Logger.debug("New message: #{message}")

    # This broadcast could be solved by optimistic response on a client
    broadcast!(socket, "new_msg", %{message: message})
    Chat.Client.send_message(socket.assigns.client_pid, message)

    {:noreply, socket}
  end
end
