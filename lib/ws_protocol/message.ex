defmodule WSProtocol.Message do
  @moduledoc """
  Base module for WS Protocol message handling.

  All WS Protocol messages are exactly 8 bytes long. For longer data (like strings),
  multiple 8-byte frames are sent.
  """

  @doc """
  Sends a single 8-byte message frame through the given socket.
  """
  @spec send_frame(:gen_tcp.socket(), binary()) :: :ok | {:error, any()}
  def send_frame(socket, data) when byte_size(data) == 8 do
    :gen_tcp.send(socket, data)
  end

  def send_frame(_socket, data) do
    {:error, {:invalid_frame_size, byte_size(data)}}
  end

  @doc """
  Receives a single 8-byte message frame from the given socket.
  """
  @spec receive_frame(:gen_tcp.socket()) :: {:ok, binary()} | {:error, any()}
  def receive_frame(socket) do
    case :gen_tcp.recv(socket, 8) do
      {:ok, data} when byte_size(data) == 8 -> {:ok, data}
      {:ok, data} -> {:error, {:invalid_frame_size, byte_size(data)}}
      error -> error
    end
  end

  @doc """
  Sends multiple 8-byte frames through the given socket.
  """
  @spec send_frames(:gen_tcp.socket(), [binary()]) :: :ok | {:error, any()}
  def send_frames(socket, frames) do
    Enum.reduce_while(frames, :ok, fn frame, :ok ->
      case send_frame(socket, frame) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Receives multiple 8-byte frames from the given socket.
  """
  @spec receive_frames(:gen_tcp.socket(), non_neg_integer()) :: {:ok, [binary()]} | {:error, any()}
  def receive_frames(socket, count) do
    receive_frames_acc(socket, count, [])
  end

  defp receive_frames_acc(_socket, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp receive_frames_acc(socket, count, acc) do
    case receive_frame(socket) do
      {:ok, frame} -> receive_frames_acc(socket, count - 1, [frame | acc])
      error -> error
    end
  end

  @doc """
  Pads data to be a multiple of 8 bytes.
  """
  @spec pad_to_frame_size(binary()) :: binary()
  def pad_to_frame_size(data) do
    remainder = rem(byte_size(data), 8)

    if remainder == 0 do
      data
    else
      padding_size = 8 - remainder
      data <> <<0::size(padding_size)-unit(8)>>
    end
  end

  @doc """
  Calculates how many 8-byte frames are needed for the given data size.
  """
  @spec frames_needed(non_neg_integer()) :: non_neg_integer()
  def frames_needed(size) do
    div(size + 7, 8)
  end

  @doc """
  Creates a standard WS Protocol request frame.
  """
  @spec create_request_frame(WSProtocol.command(), non_neg_integer(), binary()) :: binary()
  def create_request_frame(command, tag_id, payload) when byte_size(payload) == 4 do
    command_id = WSProtocol.command_id(command)
    <<command_id::little-16, tag_id::little-16, payload::binary>>
  end

  @doc """
  Creates a standard WS Protocol response frame.
  """
  @spec create_response_frame(WSProtocol.error_code(), non_neg_integer(), binary()) :: binary()
  def create_response_frame(error_code, tag_id, payload) when byte_size(payload) == 4 do
    error_code_int = WSProtocol.error_code(error_code)
    <<error_code_int::little-16, tag_id::little-16, payload::binary>>
  end

  @doc """
  Parses a WS Protocol request frame.
  """
  @spec parse_request_frame(binary()) :: {:ok, {WSProtocol.command(), non_neg_integer(), binary()}} | {:error, any()}
  def parse_request_frame(<<command_id::little-16, tag_id::little-16, payload::binary-4>>) do
    case WSProtocol.command_from_id(command_id) do
      nil -> {:error, {:unknown_command, command_id}}
      command -> {:ok, {command, tag_id, payload}}
    end
  end

  def parse_request_frame(_), do: {:error, :invalid_frame_format}

  @doc """
  Parses a WS Protocol response frame.
  """
  @spec parse_response_frame(binary()) :: {:ok, {WSProtocol.error_code(), non_neg_integer(), binary()}} | {:error, any()}
  def parse_response_frame(<<error_code_int::little-16, tag_id::little-16, payload::binary-4>>) do
    case WSProtocol.error_from_code(error_code_int) do
      nil -> {:error, {:unknown_error_code, error_code_int}}
      error_code -> {:ok, {error_code, tag_id, payload}}
    end
  end

  def parse_response_frame(_), do: {:error, :invalid_frame_format}
end
