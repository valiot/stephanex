defmodule WSProtocol.Message.NoOp do
  @moduledoc """
  Handles NoOp (No Operation) messages for the WS Protocol.

  NoOp messages serve as heartbeat messages to check if the server is still alive
  and responding. They do nothing on the server side but allow the client to verify
  connectivity.

  Request Frame Layout:
  - Bytes 0-1: Command ID (1)
  - Bytes 2-3: Padding (0)
  - Bytes 4-7: Padding (0)

  Response Frame Layout:
  - Bytes 0-1: Return Code (0xFFFF for NoOp)
  - Bytes 2-3: Must be 0
  - Bytes 4-7: Must be 0
  """

  alias WSProtocol.Message

  @doc """
  Executes a NoOp command for the client.
  """
  @spec execute(:gen_tcp.socket()) :: :ok | {:error, any()}
  def execute(socket) do
    # Create request frame
    request_frame = Message.create_request_frame(:no_op, 0, <<0::32>>)

    with :ok <- Message.send_frame(socket, request_frame),
         {:ok, response_frame} <- Message.receive_frame(socket),
         {:ok, {error_code, tag_id, payload}} <- Message.parse_response_frame(response_frame) do
      # For NoOp, the response should have error code 0xFFFF (alive)
      case {error_code, tag_id, payload} do
        {:alive, 0, <<0::32>>} -> :ok
        _ -> {:error, :invalid_no_op_response}
      end
    end
  end

  @doc """
  Handles a NoOp command on the server side.
  """
  @spec handle_request(:gen_tcp.socket(), non_neg_integer(), binary()) :: :ok | {:error, any()}
  def handle_request(socket, tag_id, payload) do
    # Validate the request
    case {tag_id, payload} do
      {0, <<0::32>>} ->
        # Send the standard NoOp response
        response_frame = Message.create_response_frame(:alive, 0, <<0::32>>)
        Message.send_frame(socket, response_frame)

      _ ->
        # Invalid NoOp request
        error_frame = Message.create_response_frame(:implausible_argument, tag_id, <<0::32>>)
        Message.send_frame(socket, error_frame)
    end
  end
end
