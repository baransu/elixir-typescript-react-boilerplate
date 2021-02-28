import React from "react";
import socket from "../socket";

type Connection = {
  port: string;
  token: string;
};

export function ChatApp() {
  const [messages, setMessages] = React.useState([]);
  const [value, setValue] = React.useState("");
  // TODO: reducer
  const [clientConnected, setClientConnected] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [connection, setConnection] = React.useState<Connection | null>(null);
  const channelRef = React.useRef(null);

  function addMessage(message: string) {
    setMessages((messages) => [...messages, message]);
  }

  React.useEffect(() => {
    if (connection) return;

    const channel = socket.channel(`room:lobby`);

    channel
      .join()
      .receive("ok", ({ port, token }) => {
        setConnection({ token, port });
        channel.leave();
      })
      .receive("error", ({ reason }) => setError(reason));
  }, [connection]);

  React.useEffect(() => {
    if (!connection) return;

    channelRef.current = socket.channel(`room:${connection.port}`, {
      token: connection.token,
    });

    channelRef.current.join().receive("error", () => {
      channelRef.current.leave();
      setConnection(null);
      setClientConnected(false);
    });

    channelRef.current.on("new_msg", (data) => addMessage(data.message));
    channelRef.current.on("connected", () => setClientConnected(true));
    channelRef.current.on("disconnected", () => setClientConnected(false));
  }, [connection]);

  function handleChange(event: React.ChangeEvent<HTMLInputElement>) {
    setValue(event.target.value);
  }

  function handleSend(event) {
    event.preventDefault();
    channelRef.current.push("new_msg", { message: value }, 10000);
    setValue("");
  }

  if (!connection) {
    return <div>Connecting...</div>;
  }

  if (error) {
    return <div>Error: {error}</div>;
  }

  return (
    <div>
      <div>Listening on port: {connection.port}</div>
      <div>
        {messages.map((msg, index) => {
          return <div key={index}>{msg}</div>;
        })}
        {!clientConnected ? <div>Waiting for a client...</div> : null}
      </div>
      <div>
        <form onSubmit={handleSend}>
          <input value={value} onChange={handleChange} />
        </form>
        <button onClick={handleSend}>Send</button>
      </div>
    </div>
  );
}
