# Architecture

## Component overview

--8<-- "architecture/component-overview.md"

In the Ruby implementation, the core components map to these types:

- **`Session`**: The main entry point. A single class that owns connection
  details, authentication, mapping configuration, diagnostic state, and all
  148 command methods plus 16 ensure methods and 9 sync methods. Created
  via `Session.new` with keyword arguments.
- **Command methods**: Instance methods on `Session` (e.g. `display_queue`,
  `define_qlocal`, `delete_channel`). Each method is a thin wrapper that
  calls the internal `mqsc_command` dispatcher with the correct verb and
  qualifier.
- **`Mapping` module**: Internal module that handles bidirectional attribute
  translation using mapping data loaded from a bundled JSON resource. See
  the [mapping pipeline](mapping-pipeline.md) for details.
- **Error classes**: A hierarchy under `MQ::REST::Admin::Error` with specific
  subclasses (`TransportError`, `CommandError`, etc.) for `rescue` matching.

## Request lifecycle

--8<-- "architecture/request-lifecycle.md"

In Ruby, the command dispatcher is the private `mqsc_command` method on
`Session`. Every public command method (e.g. `display_queue`,
`define_qlocal`) delegates to it with the appropriate verb and qualifier.

The session retains diagnostic state from the most recent command for
inspection:

```ruby
session.display_queue(name: 'MY.QUEUE')

session.last_command_payload    # the Hash sent to MQ
session.last_response_payload   # the parsed Hash response
session.last_http_status        # HTTP status code
session.last_response_text      # raw response body
```

## Transport abstraction

--8<-- "architecture/transport-abstraction.md"

In Ruby, the transport is defined by a duck-type contract:

```ruby
# Any object responding to #post_json with this signature
def post_json(url, payload, headers:, timeout_seconds:)
  # Returns a TransportResponse
end
```

The default `NetHTTPTransport` uses `net/http`. Custom implementations can be
injected via the `transport:` keyword argument for testing or specialized HTTP
handling.

For testing, inject a mock transport:

```ruby
class MockTransport
  attr_reader :calls

  def initialize(responses: [])
    @responses = responses
    @call_index = 0
    @calls = []
  end

  def post_json(url, payload, headers:, timeout_seconds:)
    @calls << { url: url, payload: payload }
    response = @responses[@call_index]
    @call_index += 1
    response || MQ::REST::Admin::TransportResponse.new(
      status_code: 200,
      body: '{"commandResponse":[]}',
      headers: {}
    )
  end
end

session = MQ::REST::Admin::Session.new(
  'https://localhost:9443/ibmmq/rest/v2', 'QM1',
  credentials: MQ::REST::Admin::BasicAuth.new(username: 'admin', password: 'pass'),
  transport: MockTransport.new
)
```

This makes the entire command pipeline testable without an MQ server.

## Single-endpoint design

--8<-- "architecture/single-endpoint-design.md"

In Ruby, this means every command method on `Session` ultimately calls the
same `post_json` method on the transport with the same URL pattern. The only
variation is the JSON payload content.

## Gateway routing

--8<-- "architecture/gateway-routing.md"

In Ruby, configure gateway routing via a keyword argument:

```ruby
session = MQ::REST::Admin::Session.new(
  'https://qm1-host:9443/ibmmq/rest/v2',
  'QM2',                                      # target (remote) queue manager
  credentials: MQ::REST::Admin::BasicAuth.new(username: 'mqadmin', password: 'mqadmin'),
  gateway_qmgr: 'QM1'                         # local gateway queue manager
)
```

## Zero dependencies

The gem uses only the Ruby standard library:

- `net/http` for HTTP
- `json` for JSON
- `openssl` for TLS/mTLS
- `base64` for Basic auth encoding

## Ensure pipeline

See [ensure](api/ensure.md) for details on the idempotent
create-or-update pipeline.

## Sync pipeline

See [sync](api/sync.md) for details on the synchronous
polling pipeline.
