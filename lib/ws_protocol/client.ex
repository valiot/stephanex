defmodule WSProtocol.Client do
  @moduledoc """
  A GenServer implementation of the WS Protocol client.

  This module provides a client for connecting to WS Protocol servers
  and performing operations like reading/writing tag values.

  Features:
  - TCP connection management
  - Automatic heartbeat (NoOp messages)
  - Reading/writing integer, float, and string values
  - Connection monitoring and error handling
  - Timeout management

  ## Usage

      # Start a client
      {:ok, client} = WSProtocol.Client.start_link(host: "192.168.1.100", port: 5000)

      # Connect to the server
      :ok = WSProtocol.Client.connect(client)

      # Read a value
      {:ok, value} = WSProtocol.Client.read_single_value_as_int(client, 1001)

      # Write a value
      :ok = WSProtocol.Client.write_single_value(client, 1002, 42)

      # Read a string
      {:ok, string} = WSProtocol.Client.read_single_string(client, 2001)

      # Disconnect
      :ok = WSProtocol.Client.disconnect(client)
  """

  use GenServer
  require Logger

    alias WSProtocol.Message.{NoOp, ReadSingleValue, WriteSingleValue, ReadSingleString, WriteSingleString}

  @default_port 5000
  @default_timeout 5000
  @default_heartbeat_interval 20_000

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            host: String.t(),
            port: non_neg_integer(),
            socket: :gen_tcp.socket() | nil,
            timeout: non_neg_integer(),
            heartbeat_enabled: boolean(),
            heartbeat_interval: non_neg_integer(),
            heartbeat_timer: reference() | nil,
            connected: boolean()
          }

    defstruct host: nil,
              port: 5000,
              socket: nil,
              timeout: 5000,
              heartbeat_enabled: true,
              heartbeat_interval: 20_000,
              heartbeat_timer: nil,
              connected: false
  end

  # Public API

  @doc """
  Starts a new WS Protocol client.

  ## Options

  - `:host` - The hostname or IP address of the server (required)
  - `:port` - The port number (default: 5000)
  - `:timeout` - Connection and operation timeout in milliseconds (default: 5000)
  - `:heartbeat_enabled` - Whether to enable automatic heartbeat (default: true)
  - `:heartbeat_interval` - Heartbeat interval in milliseconds (default: 20000)
  - `:name` - GenServer name registration
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    host = Keyword.get(opts, :host)

    if is_nil(host) do
      raise ArgumentError, "host is required"
    end

    name = Keyword.get(opts, :name)
    gen_server_opts = if name, do: [name: name], else: []

    state = %State{
      host: to_charlist(host),
      port: Keyword.get(opts, :port, @default_port),
      timeout: Keyword.get(opts, :timeout, @default_timeout),
      heartbeat_enabled: Keyword.get(opts, :heartbeat_enabled, true),
      heartbeat_interval: Keyword.get(opts, :heartbeat_interval, @default_heartbeat_interval)
    }

    GenServer.start_link(__MODULE__, state, gen_server_opts)
  end

  @doc """
  Connects to the WS Protocol server.
  """
  @spec connect(GenServer.server()) :: :ok | {:error, any()}
  def connect(client) do
    GenServer.call(client, :connect)
  end

  @doc """
  Disconnects from the WS Protocol server.
  """
  @spec disconnect(GenServer.server()) :: :ok
  def disconnect(client) do
    GenServer.call(client, :disconnect)
  end

  @doc """
  Checks if the client is connected.
  """
  @spec connected?(GenServer.server()) :: boolean()
  def connected?(client) do
    GenServer.call(client, :connected?)
  end

  @doc """
  Sends a NoOp (heartbeat) message to the server.
  """
  @spec no_op(GenServer.server()) :: :ok | {:error, any()}
  def no_op(client) do
    GenServer.call(client, :no_op)
  end

  @doc """
  Reads a single value as an integer.
  """
  @spec read_single_value_as_int(GenServer.server(), non_neg_integer()) :: {:ok, integer()} | {:error, any()}
  def read_single_value_as_int(client, tag_id) do
    GenServer.call(client, {:read_single_value_as_int, tag_id})
  end

  @doc """
  Reads a single value as a float.
  """
  @spec read_single_value_as_float(GenServer.server(), non_neg_integer()) :: {:ok, float()} | {:error, any()}
  def read_single_value_as_float(client, tag_id) do
    GenServer.call(client, {:read_single_value_as_float, tag_id})
  end

  @doc """
  Reads a single value with the specified data type.

  The data_type parameter determines whether to read as integer or float.
  """
  @spec read_single_value(GenServer.server(), non_neg_integer(), :int | :float) :: {:ok, integer() | float()} | {:error, any()}
  def read_single_value(client, tag_id, :int) do
    read_single_value_as_int(client, tag_id)
  end

  def read_single_value(client, tag_id, :float) do
    read_single_value_as_float(client, tag_id)
  end

  @doc """
  Writes a single integer value.
  """
  @spec write_single_value(GenServer.server(), non_neg_integer(), integer()) :: :ok | {:error, any()}
  def write_single_value(client, tag_id, value) when is_integer(value) do
    GenServer.call(client, {:write_single_value_int, tag_id, value})
  end

  @spec write_single_value(GenServer.server(), non_neg_integer(), float()) :: :ok | {:error, any()}
  def write_single_value(client, tag_id, value) when is_float(value) do
    GenServer.call(client, {:write_single_value_float, tag_id, value})
  end

  @doc """
  Reads a single string value.
  """
  @spec read_single_string(GenServer.server(), non_neg_integer()) :: {:ok, String.t()} | {:error, any()}
  def read_single_string(client, tag_id) do
    GenServer.call(client, {:read_single_string, tag_id})
  end

  @doc """
  Writes a single string value.
  """
  @spec write_single_string(GenServer.server(), non_neg_integer(), String.t()) :: :ok | {:error, any()}
  def write_single_string(client, tag_id, value) when is_binary(value) do
    GenServer.call(client, {:write_single_string, tag_id, value})
  end

  # GenServer Callbacks

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:connect, _from, %State{connected: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:connect, _from, %State{} = state) do
    case :gen_tcp.connect(state.host, state.port, [:binary, packet: 0, active: false], state.timeout) do
      {:ok, socket} ->
        new_state = %{state | socket: socket, connected: true}
        new_state = start_heartbeat(new_state)
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to connect to #{state.host}:#{state.port}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:disconnect, _from, %State{} = state) do
    new_state = disconnect_internal(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:connected?, _from, %State{} = state) do
    {:reply, state.connected, state}
  end

  def handle_call(:no_op, _from, %State{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:no_op, _from, %State{socket: socket} = state) do
    result = NoOp.execute(socket)
    {:reply, result, state}
  end

  def handle_call({:read_single_value_as_int, _tag_id}, _from, %State{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:read_single_value_as_int, tag_id}, _from, %State{socket: socket} = state) do
    result = ReadSingleValue.execute_as_integer(socket, tag_id)
    {:reply, result, state}
  end

  def handle_call({:read_single_value_as_float, _tag_id}, _from, %State{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:read_single_value_as_float, tag_id}, _from, %State{socket: socket} = state) do
    result = ReadSingleValue.execute_as_float(socket, tag_id)
    {:reply, result, state}
  end

  def handle_call({:write_single_value_int, _tag_id, _value}, _from, %State{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:write_single_value_int, tag_id, value}, _from, %State{socket: socket} = state) do
    result = WriteSingleValue.execute_integer(socket, tag_id, value)
    {:reply, result, state}
  end

  def handle_call({:write_single_value_float, _tag_id, _value}, _from, %State{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:write_single_value_float, tag_id, value}, _from, %State{socket: socket} = state) do
    result = WriteSingleValue.execute_float(socket, tag_id, value)
    {:reply, result, state}
  end

  def handle_call({:read_single_string, _tag_id}, _from, %State{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:read_single_string, tag_id}, _from, %State{socket: socket} = state) do
    result = ReadSingleString.execute(socket, tag_id)
    {:reply, result, state}
  end

  def handle_call({:write_single_string, _tag_id, _value}, _from, %State{connected: false} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:write_single_string, tag_id, value}, _from, %State{socket: socket} = state) do
    result = WriteSingleString.execute(socket, tag_id, value)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:heartbeat, %State{connected: false} = state) do
    {:noreply, state}
  end

  def handle_info(:heartbeat, %State{socket: socket} = state) do
    case NoOp.execute(socket) do
      :ok ->
        new_state = schedule_heartbeat(state)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("Heartbeat failed: #{inspect(reason)}")
        new_state = disconnect_internal(state)
        {:noreply, new_state}
    end
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    disconnect_internal(state)
    :ok
  end

  # Private Functions

  defp disconnect_internal(%State{socket: nil} = state) do
    %{state | connected: false}
  end

  defp disconnect_internal(%State{socket: socket} = state) do
    :gen_tcp.close(socket)
    stop_heartbeat(state)
    %{state | socket: nil, connected: false}
  end

  defp start_heartbeat(%State{heartbeat_enabled: false} = state), do: state

  defp start_heartbeat(%State{} = state) do
    schedule_heartbeat(state)
  end

  defp schedule_heartbeat(%State{heartbeat_enabled: false} = state), do: state

  defp schedule_heartbeat(%State{} = state) do
    timer = Process.send_after(self(), :heartbeat, state.heartbeat_interval)
    %{state | heartbeat_timer: timer}
  end

  defp stop_heartbeat(%State{heartbeat_timer: nil} = state), do: state

  defp stop_heartbeat(%State{heartbeat_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | heartbeat_timer: nil}
  end
end
