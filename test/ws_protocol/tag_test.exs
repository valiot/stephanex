defmodule WSProtocol.TagTest do
  use ExUnit.Case
  doctest WSProtocol.Tag

  alias WSProtocol.Tag

  describe "new/4" do
    test "creates a new tag with default values" do
      tag = Tag.new(1001, "Test Tag", :integer)

      assert tag.tag_id == 1001
      assert tag.name == "Test Tag"
      assert tag.data_type == :integer
      assert tag.string_value == ""
      assert tag.int_value == 0
      assert tag.real_value == 0.0
      assert tag.access == :read_write
    end

    test "creates a new tag with custom values" do
      tag = Tag.new(1002, "Custom Tag", :string,
        string_value: "Hello",
        int_value: 42,
        real_value: 3.14,
        access: :read_only
      )

      assert tag.tag_id == 1002
      assert tag.name == "Custom Tag"
      assert tag.data_type == :string
      assert tag.string_value == "Hello"
      assert tag.int_value == 42
      assert tag.real_value == 3.14
      assert tag.access == :read_only
    end

    test "creates a new tag with uint values" do
      tag = Tag.new(1003, "UInt Tag", :uint, uint_value: 4294967295)

      assert tag.tag_id == 1003
      assert tag.name == "UInt Tag"
      assert tag.data_type == :uint
      assert tag.uint_value == 4294967295
      assert tag.access == :read_write
    end
  end

  describe "get_value/1" do
    test "returns integer value for integer tag" do
      tag = %Tag{data_type: :integer, int_value: 42}
      assert Tag.get_value(tag) == 42
    end

    test "returns float value for float tag" do
      tag = %Tag{data_type: :float, real_value: 3.14}
      assert Tag.get_value(tag) == 3.14
    end

    test "returns string value for string tag" do
      tag = %Tag{data_type: :string, string_value: "Hello"}
      assert Tag.get_value(tag) == "Hello"
    end

    test "returns uint value for uint tag" do
      tag = %Tag{data_type: :uint, uint_value: 4294967295}
      assert Tag.get_value(tag) == 4294967295
    end
  end

  describe "set_value/2" do
    test "sets integer value for integer tag" do
      tag = %Tag{data_type: :integer, int_value: 0}
      updated_tag = Tag.set_value(tag, 42)
      assert updated_tag.int_value == 42
    end

    test "sets float value for float tag" do
      tag = %Tag{data_type: :float, real_value: 0.0}
      updated_tag = Tag.set_value(tag, 3.14)
      assert updated_tag.real_value == 3.14
    end

    test "converts integer to float for float tag" do
      tag = %Tag{data_type: :float, real_value: 0.0}
      updated_tag = Tag.set_value(tag, 42)
      assert updated_tag.real_value == 42.0
    end

    test "sets string value for string tag" do
      tag = %Tag{data_type: :string, string_value: ""}
      updated_tag = Tag.set_value(tag, "Hello")
      assert updated_tag.string_value == "Hello"
    end

    test "sets uint value for uint tag" do
      tag = %Tag{data_type: :uint, uint_value: 0}
      updated_tag = Tag.set_value(tag, 4294967295)
      assert updated_tag.uint_value == 4294967295
    end

    test "rejects negative values for uint tag" do
      tag = %Tag{data_type: :uint, uint_value: 0}

      assert_raise FunctionClauseError, fn ->
        Tag.set_value(tag, -1)
      end
    end
  end

  describe "readable?/1" do
    test "returns true for read_only tag" do
      tag = %Tag{access: :read_only}
      assert Tag.readable?(tag) == true
    end

    test "returns true for read_write tag" do
      tag = %Tag{access: :read_write}
      assert Tag.readable?(tag) == true
    end

    test "returns false for write_only tag" do
      tag = %Tag{access: :write_only}
      assert Tag.readable?(tag) == false
    end
  end

  describe "writable?/1" do
    test "returns false for read_only tag" do
      tag = %Tag{access: :read_only}
      assert Tag.writable?(tag) == false
    end

    test "returns true for read_write tag" do
      tag = %Tag{access: :read_write}
      assert Tag.writable?(tag) == true
    end

    test "returns true for write_only tag" do
      tag = %Tag{access: :write_only}
      assert Tag.writable?(tag) == true
    end
  end

  describe "value_to_binary/1" do
    test "converts integer value to binary" do
      tag = %Tag{data_type: :integer, int_value: 42}
      binary = Tag.value_to_binary(tag)
      assert binary == <<42::little-signed-32>>
    end

    test "converts negative integer value to binary" do
      tag = %Tag{data_type: :integer, int_value: -42}
      binary = Tag.value_to_binary(tag)
      assert binary == <<-42::little-signed-32>>
    end

    test "converts float value to binary" do
      tag = %Tag{data_type: :float, real_value: 3.14}
      binary = Tag.value_to_binary(tag)
      assert binary == <<3.14::little-float-32>>
    end

    test "converts uint value to binary" do
      tag = %Tag{data_type: :uint, uint_value: 4294967295}
      binary = Tag.value_to_binary(tag)
      assert binary == <<4294967295::little-unsigned-32>>
    end

    test "returns zero for string tag" do
      tag = %Tag{data_type: :string, string_value: "Hello"}
      binary = Tag.value_to_binary(tag)
      assert binary == <<0::little-32>>
    end
  end

  describe "set_value_from_binary/2" do
    test "sets integer value from binary" do
      tag = %Tag{data_type: :integer, int_value: 0}
      binary = <<42::little-signed-32>>
      updated_tag = Tag.set_value_from_binary(tag, binary)
      assert updated_tag.int_value == 42
    end

    test "sets negative integer value from binary" do
      tag = %Tag{data_type: :integer, int_value: 0}
      binary = <<-42::little-signed-32>>
      updated_tag = Tag.set_value_from_binary(tag, binary)
      assert updated_tag.int_value == -42
    end

    test "sets uint value from binary" do
      tag = %Tag{data_type: :uint, uint_value: 0}
      binary = <<4294967295::little-unsigned-32>>
      updated_tag = Tag.set_value_from_binary(tag, binary)
      assert updated_tag.uint_value == 4294967295
    end

    test "sets float value from binary" do
      tag = %Tag{data_type: :float, real_value: 0.0}
      binary = <<3.14::little-float-32>>
      updated_tag = Tag.set_value_from_binary(tag, binary)
      assert_in_delta updated_tag.real_value, 3.14, 0.001
    end

    test "leaves string tag unchanged" do
      tag = %Tag{data_type: :string, string_value: "Hello"}
      binary = <<42::little-32>>
      updated_tag = Tag.set_value_from_binary(tag, binary)
      assert updated_tag == tag
    end
  end
end
