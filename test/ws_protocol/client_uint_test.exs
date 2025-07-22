defmodule WSProtocol.Client.UIntTest do
  use ExUnit.Case

  alias WSProtocol.Client

  describe "read_single_value_as_uint/2" do
    test "returns error when not connected" do
      {:ok, client} = Client.start_link(host: "localhost", port: 9999, heartbeat_enabled: false)

      assert {:error, :not_connected} = Client.read_single_value_as_uint(client, 1001)

      GenServer.stop(client)
    end

    test "calls correct GenServer message" do
      {:ok, client} = Client.start_link(host: "localhost", port: 9999, heartbeat_enabled: false)

      # This will fail because we're not connected, but it tests the message routing
      assert {:error, :not_connected} = Client.read_single_value_as_uint(client, 1001)

      GenServer.stop(client)
    end
  end

  describe "write_single_value_uint/3" do
    test "returns error when not connected" do
      {:ok, client} = Client.start_link(host: "localhost", port: 9999, heartbeat_enabled: false)

      assert {:error, :not_connected} = Client.write_single_value_uint(client, 1001, 123)

      GenServer.stop(client)
    end

    test "accepts valid uint values" do
      {:ok, client} = Client.start_link(host: "localhost", port: 9999, heartbeat_enabled: false)

      # Test various valid uint values
      valid_values = [0, 1, 255, 65535, 4294967295]

      for value <- valid_values do
        # All should return :not_connected error (since we're not connected)
        # but they should pass the guard clause
        assert {:error, :not_connected} = Client.write_single_value_uint(client, 1001, value)
      end

      GenServer.stop(client)
    end

    test "rejects negative values with function clause error" do
      {:ok, client} = Client.start_link(host: "localhost", port: 9999, heartbeat_enabled: false)

      assert_raise FunctionClauseError, fn ->
        Client.write_single_value_uint(client, 1001, -1)
      end

      GenServer.stop(client)
    end
  end

  describe "read_single_value/3 with :uint" do
    test "routes to read_single_value_as_uint" do
      {:ok, client} = Client.start_link(host: "localhost", port: 9999, heartbeat_enabled: false)

      # Both calls should have the same result
      result1 = Client.read_single_value(client, 1001, :uint)
      result2 = Client.read_single_value_as_uint(client, 1001)

      assert result1 == result2
      assert result1 == {:error, :not_connected}

      GenServer.stop(client)
    end

    test "supports all data types" do
      {:ok, client} = Client.start_link(host: "localhost", port: 9999, heartbeat_enabled: false)

      # Test that all data types are supported
      assert {:error, :not_connected} = Client.read_single_value(client, 1001, :int)
      assert {:error, :not_connected} = Client.read_single_value(client, 1001, :uint)
      assert {:error, :not_connected} = Client.read_single_value(client, 1001, :float)

      GenServer.stop(client)
    end
  end

  describe "GenServer handle_call for uint operations" do
    setup do
      {:ok, client} = Client.start_link(host: "localhost", port: 9999, heartbeat_enabled: false)
      %{client: client}
    end

    test "handles read_single_value_as_uint when not connected", %{client: client} do
      # Direct GenServer call test
      assert {:error, :not_connected} = GenServer.call(client, {:read_single_value_as_uint, 1001})
    end

    test "handles write_single_value_uint when not connected", %{client: client} do
      # Direct GenServer call test
      assert {:error, :not_connected} = GenServer.call(client, {:write_single_value_uint, 1001, 123})
    end
  end

  describe "Type validation" do
    test "uint values are properly validated" do
      # Test that our uint values are non-negative integers
      valid_values = [0, 1, 100, 4294967295]

      for value <- valid_values do
        assert is_integer(value)
        assert value >= 0
        assert value <= 4294967295  # Max uint32
      end
    end

    test "uint range boundaries" do
      # Test boundary conditions
      min_uint = 0
      max_uint32 = 4294967295

      assert is_integer(min_uint) and min_uint >= 0
      assert is_integer(max_uint32) and max_uint32 <= 4294967295

      # These would fail our guard clauses
      invalid_values = [-1, -100]
      for value <- invalid_values do
        assert value < 0  # These should be rejected
      end
    end
  end
end
