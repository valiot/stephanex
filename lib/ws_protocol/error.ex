defmodule WSProtocol.Error do
  @moduledoc """
  Exception raised when WS Protocol operations fail.
  """
  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}
end
