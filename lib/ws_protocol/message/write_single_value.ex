defmodule WSProtocol.Message.WriteSingleValue do
  @moduledoc """
  Handles WriteSingleValue messages for the WS Protocol.

  This message type is used to write a single tag's value as either a 32-bit integer
  or 32-bit floating point value.

  Request Frame Layout:
  - Bytes 0-1: Command ID (3)
  - Bytes 2-3: Tag ID
  - Bytes 4-7: The value to be written

  Response Frame Layout:
  - Bytes 0-1: Return Code
  - Bytes 2-3: Tag ID
  - Bytes 4-7: Padding (0)
  """

  alias WSProtocol.{Message, Tag}

  @doc """
  Executes a WriteSingleValue command for the client with raw binary data.
  """
  @spec execute(:gen_tcp.socket(), non_neg_integer(), binary()) :: :ok | {:error, any()}
  def execute(socket, tag_id, value_binary) when byte_size(value_binary) == 4 do
    # Create request frame
    request_frame = Message.create_request_frame(:write_single_value, tag_id, value_binary)

    with :ok <- Message.send_frame(socket, request_frame),
         {:ok, response_frame} <- Message.receive_frame(socket),
         {:ok, {error_code, response_tag_id, payload}} <- Message.parse_response_frame(response_frame) do
      # Check for errors
      case error_code do
        :successful ->
          # Validate the tag ID matches and payload is zeros
          if response_tag_id == tag_id and payload == <<0::32>> do
            :ok
          else
            {:error, :invalid_write_response}
          end

        _ ->
          {:error, error_code}
      end
    end
  end

  @doc """
  Executes a WriteSingleValue command for the client with an integer value.
  """
  @spec execute_integer(:gen_tcp.socket(), non_neg_integer(), integer()) :: :ok | {:error, any()}
  def execute_integer(socket, tag_id, value) when is_integer(value) do
    value_binary = <<value::little-signed-32>>
    execute(socket, tag_id, value_binary)
  end

  @doc """
  Executes a WriteSingleValue command for the client with a float value.
  """
  @spec execute_float(:gen_tcp.socket(), non_neg_integer(), float()) :: :ok | {:error, any()}
  def execute_float(socket, tag_id, value) when is_float(value) do
    value_binary = <<value::little-float-32>>
    execute(socket, tag_id, value_binary)
  end

  @doc """
  Handles a WriteSingleValue command on the server side.
  """
  @spec handle_request(
          :gen_tcp.socket(),
          non_neg_integer(),
          binary(),
          (non_neg_integer() -> Tag.t() | nil),
          (non_neg_integer(), Tag.t() -> :ok | {:error, any()})
        ) :: :ok | {:error, any()}
  def handle_request(socket, tag_id, payload, find_tag_fn, update_tag_fn) do
    # Find the requested tag
    case find_tag_fn.(tag_id) do
      nil ->
        # Tag not found
        error_frame = Message.create_response_frame(:implausible_argument, tag_id, <<0::32>>)
        Message.send_frame(socket, error_frame)

      %Tag{data_type: :string} ->
        # String tags should not be writable with write_single_value
        error_frame = Message.create_response_frame(:implausible_argument, tag_id, <<0::32>>)
        Message.send_frame(socket, error_frame)

      %Tag{} = tag ->
        # Check if the tag is writable
        if Tag.writable?(tag) do
          # Update the tag's value
          updated_tag = Tag.set_value_from_binary(tag, payload)

          case update_tag_fn.(tag_id, updated_tag) do
            :ok ->
              # Send success response
              response_frame = Message.create_response_frame(:successful, tag_id, <<0::32>>)
              Message.send_frame(socket, response_frame)

            {:error, _reason} ->
              # Failed to update tag
              error_frame = Message.create_response_frame(:write_not_successful, tag_id, <<0::32>>)
              Message.send_frame(socket, error_frame)
          end
        else
          # Tag is not writable
          error_frame = Message.create_response_frame(:unauthorized_access, tag_id, <<0::32>>)
          Message.send_frame(socket, error_frame)
        end
    end
  end
end
