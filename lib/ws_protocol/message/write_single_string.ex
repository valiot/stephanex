defmodule WSProtocol.Message.WriteSingleString do
  @moduledoc """
  Handles WriteSingleString messages for the WS Protocol.

  This message type is used to write a single tag's value as a string.
  String values can span multiple 8-byte frames.

  Request Frame Layout (First Frame):
  - Bytes 0-1: Command ID (9)
  - Bytes 2-3: Tag ID
  - Bytes 4-7: Length of string in Unicode characters (UTF-16)

  Request Frame Layout (Subsequent Frames):
  - Bytes 0-7: String data in UTF-16 encoding

  Response Frame Layout:
  - Bytes 0-1: Return Code
  - Bytes 2-3: Tag ID
  - Bytes 4-7: Padding (0)

  Note: The string length is given in Unicode characters (UTF-16), where each
  character takes 2 bytes. The last frame may contain padding to reach 8 bytes.
  """

  alias WSProtocol.{Message, Tag}

  @doc """
  Executes a WriteSingleString command for the client.
  """
  @spec execute(:gen_tcp.socket(), non_neg_integer(), String.t()) :: :ok | {:error, any()}
  def execute(socket, tag_id, string_value) do
    # Convert string to UTF-16
    case :unicode.characters_to_binary(string_value, :utf8, {:utf16, :little}) do
      {:error, _encoded, _rest} ->
        {:error, :invalid_utf8}

      {:incomplete, _encoded, _rest} ->
        {:error, :incomplete_utf8}

      utf16_data ->
        # Calculate string length in Unicode characters (UTF-16)
        string_length = div(byte_size(utf16_data), 2)

        # Create the first frame with the string length
        first_frame = Message.create_request_frame(:write_string, tag_id, <<string_length::little-32>>)

        with :ok <- Message.send_frame(socket, first_frame) do
          # Send the string data frames
          case send_string_data(socket, utf16_data) do
            :ok ->
              # Receive the response
              case Message.receive_frame(socket) do
                {:ok, response_frame} ->
                  case Message.parse_response_frame(response_frame) do
                    {:ok, {error_code, response_tag_id, payload}} ->
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

                    error ->
                      error
                  end

                error ->
                  error
              end

            error ->
              error
          end
        end
    end
  end

  @doc """
  Sends string data through the socket as multiple 8-byte frames.
  """
  @spec send_string_data(:gen_tcp.socket(), binary()) :: :ok | {:error, any()}
  def send_string_data(socket, utf16_data) do
    # Pad the string data to be a multiple of 8 bytes
    padded_data = Message.pad_to_frame_size(utf16_data)

    # Split into 8-byte frames and send
    padded_data
    |> :binary.bin_to_list()
    |> Enum.chunk_every(8)
    |> Enum.map(&:binary.list_to_bin/1)
    |> Enum.reduce_while(:ok, fn frame, :ok ->
      case Message.send_frame(socket, frame) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Handles a WriteSingleString command on the server side.
  """
  @spec handle_request(
          :gen_tcp.socket(),
          non_neg_integer(),
          binary(),
          (non_neg_integer() -> Tag.t() | nil),
          (non_neg_integer(), Tag.t() -> :ok | {:error, any()})
        ) :: :ok | {:error, any()}
  def handle_request(socket, tag_id, payload, find_tag_fn, update_tag_fn) do
    # Extract string length from payload
    <<string_length::little-32>> = payload

    # Find the requested tag
    case find_tag_fn.(tag_id) do
      nil ->
        # Tag not found
        error_frame = Message.create_response_frame(:implausible_argument, tag_id, <<0::32>>)
        Message.send_frame(socket, error_frame)

      %Tag{data_type: :string} = tag ->
        # Check if the tag is writable
        if Tag.writable?(tag) do
          # Receive the string data
          case receive_string_data(socket, string_length) do
            {:ok, string_value} ->
              # Update the tag's value
              updated_tag = Tag.set_value(tag, string_value)

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

            {:error, _reason} ->
              # Failed to receive string data
              error_frame = Message.create_response_frame(:implausible_argument, tag_id, <<0::32>>)
              Message.send_frame(socket, error_frame)
          end
        else
          # Tag is not writable
          error_frame = Message.create_response_frame(:unauthorized_access, tag_id, <<0::32>>)
          Message.send_frame(socket, error_frame)
        end

             %Tag{data_type: data_type} when data_type != :string ->
         # Tag exists but is not a string type
         error_frame = Message.create_response_frame(:implausible_argument, tag_id, <<0::32>>)
         Message.send_frame(socket, error_frame)
    end
  end

  @doc """
  Receives string data from the socket based on the provided length.
  """
  @spec receive_string_data(:gen_tcp.socket(), non_neg_integer()) :: {:ok, String.t()} | {:error, any()}
  def receive_string_data(socket, string_length) do
    # Calculate how many bytes we need to read (UTF-16 = 2 bytes per character)
    byte_length = string_length * 2

    # Calculate how many frames we need to receive
    frames_needed = Message.frames_needed(byte_length)

    case Message.receive_frames(socket, frames_needed) do
      {:ok, frames} ->
        # Concatenate all frame data
        string_data =
          frames
          |> Enum.join()
          |> binary_part(0, byte_length)  # Remove any padding

                 # Convert from UTF-16 to UTF-8
         case :unicode.characters_to_binary(string_data, {:utf16, :little}, :utf8) do
           {:error, _encoded, _rest} -> {:error, :invalid_utf16}
           {:incomplete, _encoded, _rest} -> {:error, :incomplete_utf16}
           utf8_string -> {:ok, utf8_string}
         end

      error ->
        error
    end
  end
end
