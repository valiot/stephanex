defmodule WSProtocolTest do
  use ExUnit.Case
  doctest WSProtocol

  alias WSProtocol

  describe "command_id/1" do
    test "returns correct command IDs" do
      assert WSProtocol.command_id(:no_op) == 1
      assert WSProtocol.command_id(:read_single_value) == 2
      assert WSProtocol.command_id(:write_single_value) == 3
      assert WSProtocol.command_id(:read_list) == 4
      assert WSProtocol.command_id(:write_list) == 5
      assert WSProtocol.command_id(:read_string) == 8
      assert WSProtocol.command_id(:write_string) == 9
    end
  end

  describe "command_from_id/1" do
    test "returns correct command atoms" do
      assert WSProtocol.command_from_id(1) == :no_op
      assert WSProtocol.command_from_id(2) == :read_single_value
      assert WSProtocol.command_from_id(3) == :write_single_value
      assert WSProtocol.command_from_id(4) == :read_list
      assert WSProtocol.command_from_id(5) == :write_list
      assert WSProtocol.command_from_id(8) == :read_string
      assert WSProtocol.command_from_id(9) == :write_string
    end

    test "returns nil for unknown command ID" do
      assert WSProtocol.command_from_id(99) == nil
    end
  end

  describe "error_code/1" do
    test "returns correct error codes" do
      assert WSProtocol.error_code(:successful) == 0x0000
      assert WSProtocol.error_code(:write_not_successful) == 0x8888
      assert WSProtocol.error_code(:memory_overflow) == 0x9999
      assert WSProtocol.error_code(:unknown_cmd) == 0xAAAA
      assert WSProtocol.error_code(:unauthorized_access) == 0xBBBB
      assert WSProtocol.error_code(:server_overload) == 0xCCCC
      assert WSProtocol.error_code(:implausible_argument) == 0xDDDD
      assert WSProtocol.error_code(:implausible_list) == 0xEEEE
      assert WSProtocol.error_code(:alive) == 0xFFFF
    end
  end

  describe "error_from_code/1" do
    test "returns correct error atoms" do
      assert WSProtocol.error_from_code(0x0000) == :successful
      assert WSProtocol.error_from_code(0x8888) == :write_not_successful
      assert WSProtocol.error_from_code(0x9999) == :memory_overflow
      assert WSProtocol.error_from_code(0xAAAA) == :unknown_cmd
      assert WSProtocol.error_from_code(0xBBBB) == :unauthorized_access
      assert WSProtocol.error_from_code(0xCCCC) == :server_overload
      assert WSProtocol.error_from_code(0xDDDD) == :implausible_argument
      assert WSProtocol.error_from_code(0xEEEE) == :implausible_list
      assert WSProtocol.error_from_code(0xFFFF) == :alive
    end

    test "returns nil for unknown error code" do
      assert WSProtocol.error_from_code(0x1234) == nil
    end
  end

  describe "check_error_code!/1" do
    test "returns :ok for successful code" do
      assert WSProtocol.check_error_code!(0x0000) == :ok
    end

    test "raises WSProtocol.Error for error codes" do
      assert_raise WSProtocol.Error, "The value could not be written", fn ->
        WSProtocol.check_error_code!(0x8888)
      end

      assert_raise WSProtocol.Error, "Memory overflow occurred", fn ->
        WSProtocol.check_error_code!(0x9999)
      end

      assert_raise WSProtocol.Error, "The requested command is unknown", fn ->
        WSProtocol.check_error_code!(0xAAAA)
      end

      assert_raise WSProtocol.Error, "The value could not be written because it is read only", fn ->
        WSProtocol.check_error_code!(0xBBBB)
      end

      assert_raise WSProtocol.Error, "The server is currently overloaded", fn ->
        WSProtocol.check_error_code!(0xCCCC)
      end

      assert_raise WSProtocol.Error, "The given TagId is not available on the server", fn ->
        WSProtocol.check_error_code!(0xDDDD)
      end

      assert_raise WSProtocol.Error, "A list given in the request is not plausible", fn ->
        WSProtocol.check_error_code!(0xEEEE)
      end

      assert_raise WSProtocol.Error, "Server alive check failed", fn ->
        WSProtocol.check_error_code!(0xFFFF)
      end
    end

    test "raises WSProtocol.Error for unknown error codes" do
      assert_raise WSProtocol.Error, "Unknown error code: 4660", fn ->
        WSProtocol.check_error_code!(0x1234)
      end
    end
  end

  describe "message_frame_length/0" do
    test "returns 8" do
      assert WSProtocol.message_frame_length() == 8
    end
  end
end
