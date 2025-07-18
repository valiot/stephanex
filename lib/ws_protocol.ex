defmodule WSProtocol do
  @moduledoc """
  Elixir implementation of the Weihenstephan Standards Protocol (WS Protocol).

  This library provides a complete implementation of the WS Protocol, a binary TCP-based
  protocol used for data exchange between industrial beverage filling machines and
  Data Acquisition systems/Manufacturing Execution Systems.

  The protocol uses 8-byte message frames over TCP and supports operations like:
  - NoOp (heartbeat)
  - Reading/Writing single values (integer/float)
  - Reading/Writing string values

  ## Usage

  ### Client

      {:ok, client} = WSProtocol.Client.start_link(host: "192.168.1.100", port: 5000)
      WSProtocol.Client.connect(client)

      # Read a value
      {:ok, value} = WSProtocol.Client.read_single_value_as_int(client, 1001)

      # Write a value
      :ok = WSProtocol.Client.write_single_value(client, 1002, 42)

  ### Server

      {:ok, server} = WSProtocol.Server.start_link(port: 5000)
      WSProtocol.Server.add_tag(server, %WSProtocol.Tag{
        tag_id: 1001,
        name: "Production Counter",
        data_type: :integer,
        int_value: 0,
        access: :read_write
      })
  """

  @type command ::
          :no_op
          | :read_single_value
          | :write_single_value
          | :read_list
          | :write_list
          | :read_string
          | :write_string

  @type error_code ::
          :successful
          | :write_not_successful
          | :memory_overflow
          | :unknown_cmd
          | :unauthorized_access
          | :server_overload
          | :implausible_argument
          | :implausible_list
          | :alive

  @type data_type :: :integer | :float | :string

  @type data_access :: :read_only | :write_only | :read_write

  # Message frame length is always 8 bytes
  @ws_message_frame_length 8

  # Command IDs
  @ws_commands %{
    no_op: 1,
    read_single_value: 2,
    write_single_value: 3,
    read_list: 4,
    write_list: 5,
    read_string: 8,
    write_string: 9
  }

  # Error codes
  @ws_errors %{
    successful: 0x0000,
    write_not_successful: 0x8888,
    memory_overflow: 0x9999,
    unknown_cmd: 0xAAAA,
    unauthorized_access: 0xBBBB,
    server_overload: 0xCCCC,
    implausible_argument: 0xDDDD,
    implausible_list: 0xEEEE,
    alive: 0xFFFF
  }

  @doc """
  Returns the message frame length (always 8 bytes).
  """
  @spec message_frame_length() :: 8
  def message_frame_length, do: @ws_message_frame_length

  @doc """
  Returns the command ID for the given command atom.
  """
  @spec command_id(command()) :: non_neg_integer()
  def command_id(command), do: Map.get(@ws_commands, command)

  @doc """
  Returns the command atom for the given command ID.
  """
  @spec command_from_id(non_neg_integer()) :: command() | nil
  def command_from_id(id) do
    @ws_commands
    |> Enum.find(fn {_command, command_id} -> command_id == id end)
    |> case do
      {command, _id} -> command
      nil -> nil
    end
  end

  @doc """
  Returns the error code for the given error atom.
  """
  @spec error_code(error_code()) :: non_neg_integer()
  def error_code(error), do: Map.get(@ws_errors, error)

  @doc """
  Returns the error atom for the given error code.
  """
  @spec error_from_code(non_neg_integer()) :: error_code() | nil
  def error_from_code(code) do
    @ws_errors
    |> Enum.find(fn {_error, error_code} -> error_code == code end)
    |> case do
      {error, _code} -> error
      nil -> nil
    end
  end

  @doc """
  Raises a WSProtocol.Error for the given error code.
  """
  @spec raise_error!(non_neg_integer()) :: no_return()
  def raise_error!(code) do
    case error_from_code(code) do
      :successful ->
        :ok

      :write_not_successful ->
        raise WSProtocol.Error, "The value could not be written"

      :memory_overflow ->
        raise WSProtocol.Error, "Memory overflow occurred"

      :unknown_cmd ->
        raise WSProtocol.Error, "The requested command is unknown"

      :unauthorized_access ->
        raise WSProtocol.Error, "The value could not be written because it is read only"

      :server_overload ->
        raise WSProtocol.Error, "The server is currently overloaded"

      :implausible_argument ->
        raise WSProtocol.Error, "The given TagId is not available on the server"

      :implausible_list ->
        raise WSProtocol.Error, "A list given in the request is not plausible"

      :alive ->
        raise WSProtocol.Error, "Server alive check failed"

      nil ->
        raise WSProtocol.Error, "Unknown error code: #{code}"
    end
  end

  @doc """
  Checks an error code and raises if it's not successful.
  """
  @spec check_error_code!(non_neg_integer()) :: :ok
  def check_error_code!(0x0000), do: :ok
  def check_error_code!(code), do: raise_error!(code)
end
