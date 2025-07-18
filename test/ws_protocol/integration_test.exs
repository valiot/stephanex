defmodule WSProtocol.IntegrationTest do
  use ExUnit.Case

  alias WSProtocol.{Client, Server, Tag}

  @test_port 15000

  setup do
    # Start server
    {:ok, server} = Server.start_link(port: @test_port)

    # Add some test tags
    integer_tag = Tag.new(1001, "Integer Tag", :integer, int_value: 42)
    float_tag = Tag.new(1002, "Float Tag", :float, real_value: 3.14)
    string_tag = Tag.new(1003, "String Tag", :string, string_value: "Hello World")
    read_only_tag = Tag.new(1004, "Read Only Tag", :integer, int_value: 100, access: :read_only)
    write_only_tag = Tag.new(1005, "Write Only Tag", :integer, int_value: 200, access: :write_only)

    :ok = Server.add_tag(server, integer_tag)
    :ok = Server.add_tag(server, float_tag)
    :ok = Server.add_tag(server, string_tag)
    :ok = Server.add_tag(server, read_only_tag)
    :ok = Server.add_tag(server, write_only_tag)

    # Start client
    {:ok, client} = Client.start_link(host: "localhost", port: @test_port, heartbeat_enabled: false)

    # Connect client
    :ok = Client.connect(client)

    on_exit(fn ->
      try do
        if Process.alive?(client), do: Client.disconnect(client)
      catch
        :exit, _ -> :ok
      end

      try do
        if Process.alive?(server), do: Server.stop(server)
      catch
        :exit, _ -> :ok
      end

      Process.sleep(100)  # Give time for cleanup
    end)

    %{server: server, client: client}
  end

  describe "NoOp (heartbeat)" do
    test "client can send heartbeat to server", %{client: client} do
      assert :ok = Client.no_op(client)
    end
  end

  describe "Read/Write Integer Values" do
    test "client can read integer value from server", %{client: client} do
      assert {:ok, 42} = Client.read_single_value_as_int(client, 1001)
    end

    test "client can write integer value to server", %{client: client, server: server} do
      # Write new value
      assert :ok = Client.write_single_value(client, 1001, 123)

      # Verify it was written
      assert {:ok, 123} = Client.read_single_value_as_int(client, 1001)

      # Verify server state
      assert {:ok, tag} = Server.get_tag(server, 1001)
      assert tag.int_value == 123
    end

    test "client cannot read from write-only tag", %{client: client} do
      assert {:error, :unauthorized_access} = Client.read_single_value_as_int(client, 1005)
    end

    test "client cannot write to read-only tag", %{client: client} do
      assert {:error, :unauthorized_access} = Client.write_single_value(client, 1004, 999)
    end
  end

  describe "Read/Write Float Values" do
    test "client can read float value from server", %{client: client} do
      assert {:ok, value} = Client.read_single_value_as_float(client, 1002)
      assert_in_delta value, 3.14, 0.001
    end

    test "client can write float value to server", %{client: client, server: server} do
      # Write new value
      assert :ok = Client.write_single_value(client, 1002, 2.71)

      # Verify it was written
      assert {:ok, value} = Client.read_single_value_as_float(client, 1002)
      assert_in_delta value, 2.71, 0.001

      # Verify server state
      assert {:ok, tag} = Server.get_tag(server, 1002)
      assert_in_delta tag.real_value, 2.71, 0.001
    end
  end

  describe "Read/Write String Values" do
    test "client can read string value from server", %{client: client} do
      assert {:ok, "Hello World"} = Client.read_single_string(client, 1003)
    end

    test "client can write string value to server", %{client: client, server: server} do
      # Write new value
      assert :ok = Client.write_single_string(client, 1003, "Updated String")

      # Verify it was written
      assert {:ok, "Updated String"} = Client.read_single_string(client, 1003)

      # Verify server state
      assert {:ok, tag} = Server.get_tag(server, 1003)
      assert tag.string_value == "Updated String"
    end

    test "client can write empty string", %{client: client} do
      assert :ok = Client.write_single_string(client, 1003, "")
      assert {:ok, ""} = Client.read_single_string(client, 1003)
    end

    test "client can write string with special characters", %{client: client} do
      special_string = "Special: äöü ñ 中文 🚀"
      assert :ok = Client.write_single_string(client, 1003, special_string)
      assert {:ok, ^special_string} = Client.read_single_string(client, 1003)
    end
  end

  describe "Error Handling" do
    test "client gets error for non-existent tag", %{client: client} do
      assert {:error, :implausible_argument} = Client.read_single_value_as_int(client, 9999)
    end

    test "client gets error when reading string as integer", %{client: client} do
      # String tags should not be readable with read_single_value
      assert {:error, :implausible_argument} = Client.read_single_value_as_int(client, 1003)
    end

    test "client gets error when writing string to integer tag", %{client: client} do
      # Integer tags should not be writable with write_single_string
      assert {:error, :implausible_argument} = Client.write_single_string(client, 1001, "test")
    end
  end

  describe "Multiple Clients" do
    test "server can handle multiple clients", %{server: server} do
      # Start additional clients
      {:ok, client2} = Client.start_link(host: "localhost", port: @test_port, heartbeat_enabled: false)
      {:ok, client3} = Client.start_link(host: "localhost", port: @test_port, heartbeat_enabled: false)

      :ok = Client.connect(client2)
      :ok = Client.connect(client3)

      # All clients should be able to read values
      assert {:ok, 42} = Client.read_single_value_as_int(client2, 1001)
      assert {:ok, 42} = Client.read_single_value_as_int(client3, 1001)

      # Check server client count
      assert Server.client_count(server) == 3

      # Cleanup
      Client.disconnect(client2)
      Client.disconnect(client3)

      # Give time for cleanup
      Process.sleep(100)

      # Client count should be back to 1
      assert Server.client_count(server) == 1
    end
  end

  describe "Connection Management" do
    test "client can disconnect and reconnect", %{client: client} do
      # Disconnect
      assert :ok = Client.disconnect(client)
      assert Client.connected?(client) == false

      # Should get error when trying to read while disconnected
      assert {:error, :not_connected} = Client.read_single_value_as_int(client, 1001)

      # Reconnect
      assert :ok = Client.connect(client)
      assert Client.connected?(client) == true

      # Should work again
      assert {:ok, 42} = Client.read_single_value_as_int(client, 1001)
    end
  end

  describe "Tag Management" do
    test "server can add, update, and remove tags", %{server: server, client: client} do
      # Add new tag
      new_tag = Tag.new(2001, "New Tag", :integer, int_value: 999)
      :ok = Server.add_tag(server, new_tag)

      # Client should be able to read it
      assert {:ok, 999} = Client.read_single_value_as_int(client, 2001)

      # Update tag value
      :ok = Server.update_tag_value(server, 2001, 888)

      # Client should see updated value
      assert {:ok, 888} = Client.read_single_value_as_int(client, 2001)

      # Remove tag
      :ok = Server.remove_tag(server, 2001)

      # Client should get error
      assert {:error, :implausible_argument} = Client.read_single_value_as_int(client, 2001)
    end

    test "server can list all tags", %{server: server} do
      tags = Server.list_tags(server)
      assert length(tags) == 5

      tag_ids = Enum.map(tags, & &1.tag_id)
      assert 1001 in tag_ids
      assert 1002 in tag_ids
      assert 1003 in tag_ids
      assert 1004 in tag_ids
      assert 1005 in tag_ids
    end
  end
end
