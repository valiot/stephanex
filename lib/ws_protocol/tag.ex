defmodule WSProtocol.Tag do
  @moduledoc """
  Represents a WS Protocol tag on the server side.

  Tags are data points that hold production-related information such as:
  - Machine Operating State
  - Current Bottles per Hour
  - Total Filled Bottles
  - Total Bad Product
  - etc.

  Each tag has a unique ID, a name, a data type, and access permissions.
  """

  @type t :: %__MODULE__{
          tag_id: non_neg_integer(),
          name: String.t(),
          data_type: WSProtocol.data_type(),
          string_value: String.t(),
          int_value: integer(),
          uint_value: non_neg_integer(),
          real_value: float(),
          access: WSProtocol.data_access()
        }

  defstruct tag_id: 0,
            name: "",
            data_type: :integer,
            string_value: "",
            int_value: 0,
            uint_value: 0,
            real_value: 0.0,
            access: :read_write

  @doc """
  Creates a new tag with the given parameters.

  ## Examples

      iex> WSProtocol.Tag.new(1001, "Production Counter", :integer, int_value: 42)
      %WSProtocol.Tag{
        tag_id: 1001,
        name: "Production Counter",
        data_type: :integer,
        int_value: 42,
        access: :read_write
      }
  """
  @spec new(non_neg_integer(), String.t(), WSProtocol.data_type(), keyword()) :: t()
  def new(tag_id, name, data_type, opts \\ []) do
    %__MODULE__{
      tag_id: tag_id,
      name: name,
      data_type: data_type,
      string_value: Keyword.get(opts, :string_value, ""),
      int_value: Keyword.get(opts, :int_value, 0),
      uint_value: Keyword.get(opts, :uint_value, 0),
      real_value: Keyword.get(opts, :real_value, 0.0),
      access: Keyword.get(opts, :access, :read_write)
    }
  end

  @doc """
  Gets the current value of the tag based on its data type.

  ## Examples

      iex> tag = %WSProtocol.Tag{data_type: :integer, int_value: 42}
      iex> WSProtocol.Tag.get_value(tag)
      42

      iex> tag = %WSProtocol.Tag{data_type: :string, string_value: "Hello"}
      iex> WSProtocol.Tag.get_value(tag)
      "Hello"
  """
  @spec get_value(t()) :: integer() | non_neg_integer() | float() | String.t()
  def get_value(%__MODULE__{data_type: :integer, int_value: value}), do: value
  def get_value(%__MODULE__{data_type: :uint, uint_value: value}), do: value
  def get_value(%__MODULE__{data_type: :float, real_value: value}), do: value
  def get_value(%__MODULE__{data_type: :string, string_value: value}), do: value

  @doc """
  Sets the value of the tag based on its data type.

  ## Examples

      iex> tag = %WSProtocol.Tag{data_type: :integer}
      iex> WSProtocol.Tag.set_value(tag, 42)
      %WSProtocol.Tag{data_type: :integer, int_value: 42}
  """
  @spec set_value(t(), integer() | non_neg_integer() | float() | String.t()) :: t()
  def set_value(%__MODULE__{data_type: :integer} = tag, value) when is_integer(value) do
    %{tag | int_value: value}
  end

  def set_value(%__MODULE__{data_type: :uint} = tag, value) when is_integer(value) and value >= 0 do
    %{tag | uint_value: value}
  end

  def set_value(%__MODULE__{data_type: :float} = tag, value) when is_number(value) do
    %{tag | real_value: value * 1.0}
  end

  def set_value(%__MODULE__{data_type: :string} = tag, value) when is_binary(value) do
    %{tag | string_value: value}
  end

  @doc """
  Checks if the tag can be read based on its access permissions.
  """
  @spec readable?(t()) :: boolean()
  def readable?(%__MODULE__{access: :read_only}), do: true
  def readable?(%__MODULE__{access: :read_write}), do: true
  def readable?(%__MODULE__{access: :write_only}), do: false

  @doc """
  Checks if the tag can be written based on its access permissions.
  """
  @spec writable?(t()) :: boolean()
  def writable?(%__MODULE__{access: :write_only}), do: true
  def writable?(%__MODULE__{access: :read_write}), do: true
  def writable?(%__MODULE__{access: :read_only}), do: false

  @doc """
  Converts the tag's current value to a 4-byte binary representation.
  Used for sending values over the WS Protocol.
  """
  @spec value_to_binary(t()) :: binary()
  def value_to_binary(%__MODULE__{data_type: :integer, int_value: value}) do
    <<value::little-signed-32>>
  end

  def value_to_binary(%__MODULE__{data_type: :uint, uint_value: value}) do
    <<value::little-unsigned-32>>
  end

  def value_to_binary(%__MODULE__{data_type: :float, real_value: value}) do
    <<value::little-float-32>>
  end

  def value_to_binary(%__MODULE__{data_type: :string}) do
    # For strings, we return the length as a 32-bit integer
    # The actual string data is sent separately
    <<0::little-32>>
  end

  @doc """
  Sets the tag's value from a 4-byte binary representation.
  Used for receiving values over the WS Protocol.
  """
  @spec set_value_from_binary(t(), binary()) :: t()
  def set_value_from_binary(%__MODULE__{data_type: :integer} = tag, <<value::little-signed-32>>) do
    %{tag | int_value: value}
  end

  def set_value_from_binary(%__MODULE__{data_type: :uint} = tag, <<value::little-unsigned-32>>) do
    %{tag | uint_value: value}
  end

  def set_value_from_binary(%__MODULE__{data_type: :float} = tag, <<value::little-float-32>>) do
    %{tag | real_value: value}
  end

  def set_value_from_binary(%__MODULE__{data_type: :string} = tag, _binary) do
    # For strings, the binary doesn't contain the actual string value
    # The string is sent separately in multiple frames
    tag
  end
end
