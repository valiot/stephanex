defmodule WSProtocol.Server do
  @moduledoc """
  A GenServer implementation of the WS Protocol server.

  This module provides a server that can accept WS Protocol client connections
  and handle requests for reading/writing tag values.

  Features:
  - TCP listener accepting multiple client connections
  - Tag management and storage
  - Concurrent client handling
  - Request processing for all WS Protocol commands
  - Connection monitoring

  ## Usage

      # Start a server
      {:ok, server} = WSProtocol.Server.start_link(port: 5000)

      # Add tags
      tag = WSProtocol.Tag.new(1001, "Production Counter", :integer, int_value: 0)
      :ok = WSProtocol.Server.add_tag(server, tag)

      # Update tag value
      :ok = WSProtocol.Server.update_tag_value(server, 1001, 42)

      # Get tag
      {:ok, tag} = WSProtocol.Server.get_tag(server, 1001)
  """

  use GenServer
  require Logger

    alias WSProtocol.{Tag, Message}
  alias WSProtocol.Message.{NoOp, ReadSingleValue, WriteSingleValue, ReadSingleString, WriteSingleString}

  @default_port 5000

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            port: non_neg_integer(),
            listen_socket: :gen_tcp.socket() | nil,
            tags: %{non_neg_integer() => Tag.t()},
            clients: %{pid() => :gen_tcp.socket()},
            acceptor_pid: pid() | nil
          }

    defstruct port: 5000,
              listen_socket: nil,
              tags: %{},
              clients: %{},
              acceptor_pid: nil
  end

  # Public API

  @doc """
  Starts a new WS Protocol server.

  ## Options

  - `:port` - The port number to listen on (default: 5000)
  - `:name` - GenServer name registration
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    port = Keyword.get(opts, :port, @default_port)
    name = Keyword.get(opts, :name)
    gen_server_opts = if name, do: [name: name], else: []

    state = %State{port: port}

    GenServer.start_link(__MODULE__, state, gen_server_opts)
  end

  @doc """
  Adds a tag to the server.
  """
  @spec add_tag(GenServer.server(), Tag.t()) :: :ok
  def add_tag(server, %Tag{} = tag) do
    GenServer.call(server, {:add_tag, tag})
  end

  @doc """
  Gets a tag from the server.
  """
  @spec get_tag(GenServer.server(), non_neg_integer()) :: {:ok, Tag.t()} | {:error, :not_found}
  def get_tag(server, tag_id) do
    GenServer.call(server, {:get_tag, tag_id})
  end

  @doc """
  Updates a tag's value.
  """
  @spec update_tag_value(GenServer.server(), non_neg_integer(), any()) :: :ok | {:error, any()}
  def update_tag_value(server, tag_id, value) do
    GenServer.call(server, {:update_tag_value, tag_id, value})
  end

  @doc """
  Removes a tag from the server.
  """
  @spec remove_tag(GenServer.server(), non_neg_integer()) :: :ok
  def remove_tag(server, tag_id) do
    GenServer.call(server, {:remove_tag, tag_id})
  end

  @doc """
  Lists all tags on the server.
  """
  @spec list_tags(GenServer.server()) :: [Tag.t()]
  def list_tags(server) do
    GenServer.call(server, :list_tags)
  end

  @doc """
  Gets the number of connected clients.
  """
  @spec client_count(GenServer.server()) :: non_neg_integer()
  def client_count(server) do
    GenServer.call(server, :client_count)
  end

  @doc """
  Stops the server.
  """
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server)
  end

  # GenServer Callbacks

  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)

    case :gen_tcp.listen(state.port, [:binary, packet: 0, active: false, reuseaddr: true]) do
      {:ok, listen_socket} ->
        Logger.info("WS Protocol server listening on port #{state.port}")
        new_state = %{state | listen_socket: listen_socket}
        new_state = start_acceptor(new_state)
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to start WS Protocol server on port #{state.port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:add_tag, %Tag{tag_id: tag_id} = tag}, _from, %State{} = state) do
    new_tags = Map.put(state.tags, tag_id, tag)
    new_state = %{state | tags: new_tags}
    Logger.debug("Added tag #{tag_id}: #{tag.name}")
    {:reply, :ok, new_state}
  end

  def handle_call({:get_tag, tag_id}, _from, %State{} = state) do
    case Map.get(state.tags, tag_id) do
      nil -> {:reply, {:error, :not_found}, state}
      tag -> {:reply, {:ok, tag}, state}
    end
  end

  def handle_call({:update_tag_value, tag_id, value}, _from, %State{} = state) do
    case Map.get(state.tags, tag_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      tag ->
        try do
          updated_tag = Tag.set_value(tag, value)
          new_tags = Map.put(state.tags, tag_id, updated_tag)
          new_state = %{state | tags: new_tags}
          {:reply, :ok, new_state}
        rescue
          _ -> {:reply, {:error, :invalid_value}, state}
        end
    end
  end

  def handle_call({:remove_tag, tag_id}, _from, %State{} = state) do
    new_tags = Map.delete(state.tags, tag_id)
    new_state = %{state | tags: new_tags}
    Logger.debug("Removed tag #{tag_id}")
    {:reply, :ok, new_state}
  end

  def handle_call(:list_tags, _from, %State{} = state) do
    tags = Map.values(state.tags)
    {:reply, tags, state}
  end

  def handle_call(:client_count, _from, %State{} = state) do
    count = map_size(state.clients)
    {:reply, count, state}
  end

  @impl true
  def handle_info({:client_connected, client_pid, socket}, %State{} = state) do
    Process.monitor(client_pid)
    new_clients = Map.put(state.clients, client_pid, socket)
    new_state = %{state | clients: new_clients}
    Logger.debug("Client connected: #{inspect(client_pid)}")
    {:noreply, new_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %State{} = state) do
    case Map.get(state.clients, pid) do
      nil ->
        # Not a client process, might be the acceptor
        if pid == state.acceptor_pid do
          Logger.warning("Acceptor process died, restarting...")
          new_state = start_acceptor(%{state | acceptor_pid: nil})
          {:noreply, new_state}
        else
          {:noreply, state}
        end

      socket ->
        # Client process died
        :gen_tcp.close(socket)
        new_clients = Map.delete(state.clients, pid)
        new_state = %{state | clients: new_clients}
        Logger.debug("Client disconnected: #{inspect(pid)}")
        {:noreply, new_state}
    end
  end

  @impl true
  def terminate(_reason, %State{} = state) do
    if state.listen_socket do
      :gen_tcp.close(state.listen_socket)
    end

    # Close all client connections
    for {_pid, socket} <- state.clients do
      :gen_tcp.close(socket)
    end

    Logger.info("WS Protocol server stopped")
    :ok
  end

  # Private Functions

  defp start_acceptor(%State{listen_socket: listen_socket} = state) do
    server_pid = self()
    acceptor_pid = spawn_link(fn -> acceptor_loop(listen_socket, server_pid) end)
    %{state | acceptor_pid: acceptor_pid}
  end

  defp acceptor_loop(listen_socket, server_pid) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        client_pid = spawn_link(fn -> client_loop(socket, server_pid) end)
        :gen_tcp.controlling_process(socket, client_pid)
        send(server_pid, {:client_connected, client_pid, socket})
        acceptor_loop(listen_socket, server_pid)

      {:error, reason} ->
        Logger.error("Accept failed: #{inspect(reason)}")
        # Wait a bit before retrying
        Process.sleep(1000)
        acceptor_loop(listen_socket, server_pid)
    end
  end

  defp client_loop(socket, server_pid) do
    case Message.receive_frame(socket) do
      {:ok, frame} ->
        case Message.parse_request_frame(frame) do
          {:ok, {command, tag_id, payload}} ->
            handle_client_request(socket, server_pid, command, tag_id, payload)
            client_loop(socket, server_pid)

          {:error, reason} ->
            Logger.warning("Invalid request frame: #{inspect(reason)}")
            send_error_response(socket, :unknown_cmd, 0)
            client_loop(socket, server_pid)
        end

      {:error, :closed} ->
        Logger.debug("Client connection closed")
        :ok

      {:error, reason} ->
        Logger.warning("Error receiving frame: #{inspect(reason)}")
        :ok
    end
  end

  defp handle_client_request(socket, server_pid, command, tag_id, payload) do
    find_tag_fn = fn tag_id ->
      case GenServer.call(server_pid, {:get_tag, tag_id}) do
        {:ok, tag} -> tag
        {:error, :not_found} -> nil
      end
    end

    update_tag_fn = fn _tag_id, updated_tag ->
      GenServer.call(server_pid, {:add_tag, updated_tag})
    end

    case command do
      :no_op ->
        NoOp.handle_request(socket, tag_id, payload)

      :read_single_value ->
        ReadSingleValue.handle_request(socket, tag_id, payload, find_tag_fn)

      :write_single_value ->
        WriteSingleValue.handle_request(socket, tag_id, payload, find_tag_fn, update_tag_fn)

      :read_string ->
        ReadSingleString.handle_request(socket, tag_id, payload, find_tag_fn)

      :write_string ->
        WriteSingleString.handle_request(socket, tag_id, payload, find_tag_fn, update_tag_fn)

      _ ->
        send_error_response(socket, :unknown_cmd, tag_id)
    end
  end

  defp send_error_response(socket, error_code, tag_id) do
    error_frame = Message.create_response_frame(error_code, tag_id, <<0::32>>)
    Message.send_frame(socket, error_frame)
  end
end
