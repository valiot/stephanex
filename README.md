# Stephanex

A complete Elixir AI re-implementation of the Weihenstephan Standards Protocol (WS Protocol) for communication between industrial beverage filling machines and Data Acquisition systems/Manufacturing Execution Systems based on [WS_Protocol](https://github.com/StefanHasensperling/WS_Protocol) repository.

## About WS Protocol

The WS Protocol is a binary TCP-based protocol used for data exchange in industrial beverage production environments. It provides a standardized way to communicate with filling machines, allowing MES applications to read production data, machine states, and control parameters.

### Key Features

- **Binary TCP Protocol**: 8-byte message frames over TCP
- **Simple Request/Response**: Easy to implement and understand
- **Tag-based Data Exchange**: Structured data points with unique IDs
- **Multiple Data Types**: Integer, Float, and String values
- **Access Control**: Read-only, write-only, and read-write permissions
- **Heartbeat Support**: Automatic connection monitoring
- **Concurrent Client Support**: Handle multiple clients simultaneously

## Installation

Add `stephanex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:stephanex, "~> 0.1.0"}
  ]
end
```

## Usage

### Creating a Server

The server listens for client connections and manages a collection of tags that represent machine data points.

```elixir
# Start a server on port 5000
{:ok, server} = WSProtocol.Server.start_link(port: 5000)

# Add tags to the server
production_counter = WSProtocol.Tag.new(1001, "Production Counter", :integer, 
  int_value: 0, 
  access: :read_write
)

machine_state = WSProtocol.Tag.new(1002, "Machine State", :integer, 
  int_value: 1, 
  access: :read_only
)

operator_message = WSProtocol.Tag.new(2001, "Operator Message", :string, 
  string_value: "Machine Ready", 
  access: :read_write
)

# Add tags to server
:ok = WSProtocol.Server.add_tag(server, production_counter)
:ok = WSProtocol.Server.add_tag(server, machine_state)
:ok = WSProtocol.Server.add_tag(server, operator_message)
```

### Creating a Client

The client connects to a server and can read/write tag values.

```elixir
# Start a client
{:ok, client} = WSProtocol.Client.start_link(host: "192.168.1.100", port: 5000)

# Connect to the server
:ok = WSProtocol.Client.connect(client)

# Check connection status
true = WSProtocol.Client.connected?(client)
```

### Reading Values

```elixir
# Read integer values
{:ok, production_count} = WSProtocol.Client.read_single_value_as_int(client, 1001)
{:ok, machine_state} = WSProtocol.Client.read_single_value_as_int(client, 1002)

# Read float values
{:ok, temperature} = WSProtocol.Client.read_single_value_as_float(client, 1003)

# Read string values
{:ok, message} = WSProtocol.Client.read_single_string(client, 2001)
```

### Writing Values

```elixir
# Write integer values
:ok = WSProtocol.Client.write_single_value(client, 1001, 1500)

# Write float values
:ok = WSProtocol.Client.write_single_value(client, 1003, 25.5)

# Write string values
:ok = WSProtocol.Client.write_single_string(client, 2001, "Production Started")
```

### Heartbeat and Connection Monitoring

```elixir
# Manual heartbeat
:ok = WSProtocol.Client.no_op(client)

# Automatic heartbeat is enabled by default
{:ok, client} = WSProtocol.Client.start_link(
  host: "192.168.1.100", 
  port: 5000,
  heartbeat_enabled: true,
  heartbeat_interval: 20_000  # 20 seconds
)
```

### Server Management

```elixir
# Update tag values on server
:ok = WSProtocol.Server.update_tag_value(server, 1001, 2000)

# Get tag information
{:ok, tag} = WSProtocol.Server.get_tag(server, 1001)

# List all tags
tags = WSProtocol.Server.list_tags(server)

# Check connected clients
client_count = WSProtocol.Server.client_count(server)

# Remove a tag
:ok = WSProtocol.Server.remove_tag(server, 1001)
```

## Tag Types and Access Control

### Data Types

- **`:integer`** - 32-bit signed integer values
- **`:float`** - 32-bit floating point values  
- **`:string`** - UTF-8 encoded strings

### Access Control

- **`:read_only`** - Tag can only be read by clients
- **`:write_only`** - Tag can only be written by clients
- **`:read_write`** - Tag can be both read and written

### Creating Tags

```elixir
# Integer tag with read-write access
counter_tag = WSProtocol.Tag.new(1001, "Bottle Counter", :integer,
  int_value: 0,
  access: :read_write
)

# Float tag with read-only access  
temperature_tag = WSProtocol.Tag.new(1002, "Temperature", :float,
  real_value: 22.5,
  access: :read_only
)

# String tag with write-only access
command_tag = WSProtocol.Tag.new(2001, "Command", :string,
  string_value: "",
  access: :write_only
)
```

## Complete Example

Here's a complete example showing a server and client working together:

```elixir
# Start server
{:ok, server} = WSProtocol.Server.start_link(port: 5000)

# Add tags
production_tag = WSProtocol.Tag.new(1001, "Production Counter", :integer, int_value: 0)
status_tag = WSProtocol.Tag.new(1002, "Status Message", :string, string_value: "Ready")

WSProtocol.Server.add_tag(server, production_tag)
WSProtocol.Server.add_tag(server, status_tag)

# Start client
{:ok, client} = WSProtocol.Client.start_link(host: "localhost", port: 5000)
WSProtocol.Client.connect(client)

# Read initial values
{:ok, 0} = WSProtocol.Client.read_single_value_as_int(client, 1001)
{:ok, "Ready"} = WSProtocol.Client.read_single_string(client, 1002)

# Update production counter
WSProtocol.Client.write_single_value(client, 1001, 100)
WSProtocol.Client.write_single_string(client, 1002, "Production Running")

# Read updated values
{:ok, 100} = WSProtocol.Client.read_single_value_as_int(client, 1001)
{:ok, "Production Running"} = WSProtocol.Client.read_single_string(client, 1002)

# Cleanup
WSProtocol.Client.disconnect(client)
WSProtocol.Server.stop(server)
```

## Protocol Commands

The WS Protocol supports the following commands:

| Command ID | Command Name | Description |
|------------|-------------|-------------|
| 1 | NoOp | Heartbeat message, no operation |
| 2 | Read Single Value | Read integer/float value |
| 3 | Write Single Value | Write integer/float value |
| 8 | Read String | Read string value |
| 9 | Write String | Write string value |

## Error Handling

The library provides comprehensive error handling:

```elixir
# Handle connection errors
case WSProtocol.Client.connect(client) do
  :ok -> :connected
  {:error, reason} -> {:connection_failed, reason}
end

# Handle read errors
case WSProtocol.Client.read_single_value_as_int(client, 9999) do
  {:ok, value} -> value
  {:error, :implausible_argument} -> :tag_not_found
  {:error, :unauthorized_access} -> :access_denied
  {:error, :not_connected} -> :client_disconnected
end
```

## Configuration Options

### Server Options

- `:port` - TCP port to listen on (default: 5000)
- `:name` - GenServer name for registration

### Client Options

- `:host` - Server hostname or IP address (required)
- `:port` - Server port (default: 5000)
- `:timeout` - Connection timeout in milliseconds (default: 5000)
- `:heartbeat_enabled` - Enable automatic heartbeat (default: true)
- `:heartbeat_interval` - Heartbeat interval in milliseconds (default: 20000)
- `:name` - GenServer name for registration

## Testing

Run the test suite:

```bash
mix test
```

The library includes comprehensive tests covering:
- Core protocol functionality
- Client-server communication
- Tag management
- Error handling
- Multi-client scenarios
- String encoding/decoding
- Connection management

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2025 VALIOT

## Contributing

We welcome contributions to the WSProtocol library! Please follow these guidelines:

1. **Fork the repository** and create a new branch for your feature or bug fix
2. **Follow the existing code style** and conventions
3. **Write comprehensive tests** for any new functionality
4. **Update documentation** as needed
5. **Ensure all tests pass** by running `mix test`
6. **Create a pull request** using the provided [pull request template](.github/pull_request_template.md)

### Development Setup

```bash
# Clone the repository
git clone https://github.com/your-org/stephanex.git
cd stephanex

# Install dependencies
mix deps.get

# Run tests
mix test

# Run tests with coverage
mix test --cover
```

### Code Style

- Follow standard Elixir conventions
- Use descriptive function and variable names
- Add comprehensive documentation with `@doc` and `@spec`
- Include examples in documentation where helpful

### Reporting Issues

If you find a bug or have a feature request, please create an issue on GitHub with:
- A clear description of the problem or feature
- Steps to reproduce (for bugs)
- Expected behavior
- Actual behavior
- Environment details (Elixir version, OS, etc.)

### Pull Request Process

1. Ensure your changes don't break existing functionality
2. Add tests for new features
3. Update documentation as needed
4. Use the pull request template to provide clear information about your changes
5. Be responsive to feedback during the review process

Thank you for contributing to WSProtocol!

