defmodule WSProtocol.Message.ReadSingleValue do
  @moduledoc """
  Handles ReadSingleValue messages for the WS Protocol.

  This message type is used to read a single tag's value as either a 32-bit integer
  or 32-bit floating point value.

  Request Frame Layout:
  - Bytes 0-1: Command ID (2)
  - Bytes 2-3: Tag ID
  - Bytes 4-7: Padding (0)

  Response Frame Layout:
  - Bytes 0-1: Return Code
  - Bytes 2-3: Tag ID
  - Bytes 4-7: The value of the requested tag
  """

  alias WSProtocol.{Message, Tag}

  @doc """
  Executes a ReadSingleValue command for the client.
  Returns the raw 4-byte binary value.
  """
  @spec execute(:gen_tcp.socket(), non_neg_integer()) :: {:ok, binary()} | {:error, any()}
  def execute(socket, tag_id) do
    # Create request frame
    request_frame = Message.create_request_frame(:read_single_value, tag_id, <<0::32>>)

    with :ok <- Message.send_frame(socket, request_frame),
         {:ok, response_frame} <- Message.receive_frame(socket),
         {:ok, {error_code, response_tag_id, payload}} <- Message.parse_response_frame(response_frame) do
      # Check for errors
      case error_code do
        :successful ->
          # Validate the tag ID matches
          if response_tag_id == tag_id do
            {:ok, payload}
          else
            {:error, :tag_id_mismatch}
          end

        _ ->
          {:error, error_code}
      end
    end
  end

  @doc """
  Executes a ReadSingleValue command and returns the value as an integer.
  """
  @spec execute_as_integer(:gen_tcp.socket(), non_neg_integer()) :: {:ok, integer()} | {:error, any()}
  def execute_as_integer(socket, tag_id) do
    case execute(socket, tag_id) do
      {:ok, <<value::little-signed-32>>} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Executes a ReadSingleValue command and returns the value as a float.
  """
  @spec execute_as_float(:gen_tcp.socket(), non_neg_integer()) :: {:ok, float()} | {:error, any()}
  def execute_as_float(socket, tag_id) do
    case execute(socket, tag_id) do
      {:ok, <<value::little-float-32>>} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Executes a ReadSingleValue command and returns the value as an unsigned integer.
  """
  @spec execute_as_uint(:gen_tcp.socket(), non_neg_integer()) :: {:ok, non_neg_integer()} | {:error, any()}
  def execute_as_uint(socket, tag_id) do
    case execute(socket, tag_id) do
      {:ok, <<value::little-unsigned-32>>} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Handles a ReadSingleValue command on the server side.
  """
  @spec handle_request(:gen_tcp.socket(), non_neg_integer(), binary(), (non_neg_integer() -> Tag.t() | nil)) ::
          :ok | {:error, any()}
  def handle_request(socket, tag_id, payload, find_tag_fn) do
    # Validate the request payload should be all zeros
    case payload do
      <<0::32>> ->
        # Find the requested tag
        case find_tag_fn.(tag_id) do
          nil ->
            # Tag not found
            error_frame = Message.create_response_frame(:implausible_argument, tag_id, <<0::32>>)
            Message.send_frame(socket, error_frame)

          %Tag{data_type: :string} ->
            # String tags should not be readable with read_single_value
            error_frame = Message.create_response_frame(:implausible_argument, tag_id, <<0::32>>)
            Message.send_frame(socket, error_frame)

          %Tag{} = tag ->
            # Check if the tag is readable
            if Tag.readable?(tag) do
              # Send the tag's value
              value_binary = Tag.value_to_binary(tag)
              response_frame = Message.create_response_frame(:successful, tag_id, value_binary)
              Message.send_frame(socket, response_frame)
            else
              # Tag is not readable
              error_frame = Message.create_response_frame(:unauthorized_access, tag_id, <<0::32>>)
              Message.send_frame(socket, error_frame)
            end
        end

      _ ->
        # Invalid payload
        error_frame = Message.create_response_frame(:implausible_argument, tag_id, <<0::32>>)
        Message.send_frame(socket, error_frame)
    end
  end
end
