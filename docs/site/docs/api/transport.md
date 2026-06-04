# Transport

## Overview

The transport layer handles HTTP communication with the MQ REST API.
mq-rest-admin uses a duck-type contract rather than a formal interface,
allowing any object that responds to `post_json` to serve as a transport.

## TransportResponse

`TransportResponse` is an immutable value object (`Data.define`) that wraps
an HTTP response:

| Field | Type | Description |
| --- | --- | --- |
| `status_code` | `Integer` | HTTP status code |
| `body` | `String` | Response body text |
| `headers` | `Hash` | Response headers |

```ruby
response = MQ::REST::Admin::TransportResponse.new(
  status_code: 200,
  body: '{"commandResponse":[]}',
  headers: { 'content-type' => 'application/json' }
)
```

## NetHTTPTransport

The default transport implementation using Ruby's `net/http` stdlib:

```ruby
transport = MQ::REST::Admin::NetHTTPTransport.new
# or with client certificates for mTLS:
transport = MQ::REST::Admin::NetHTTPTransport.new(
  client_cert: '/path/to/cert.pem',
  client_key: '/path/to/key.pem'
)
```

## Duck-type contract

Any object responding to `post_json` with the following signature can be used
as a transport:

```ruby
def post_json(url, payload, headers:, timeout_seconds:)
  # url: String - full URL
  # payload: Hash - JSON body to POST
  # headers: Hash - HTTP headers
  # timeout_seconds: Float or nil - request timeout
  #
  # Returns: TransportResponse
  # Raises: TransportError on network failure
end
```

## Custom transport injection

Pass a custom transport when creating the session:

```ruby
session = MQ::REST::Admin::Session.new(
  'https://localhost:9443/ibmmq/rest/v2', 'QM1',
  credentials: MQ::REST::Admin::BasicAuth.new(username: 'admin', password: 'admin'),
  transport: MyCustomTransport.new
)
```

## Mock transport for testing

```ruby
class MockTransport
  attr_reader :calls

  def initialize(responses: [])
    @responses = responses
    @call_index = 0
    @calls = []
  end

  def post_json(url, payload, headers:, timeout_seconds:)
    @calls << { url: url, payload: payload, headers: headers }
    response = @responses[@call_index]
    @call_index += 1
    response || MQ::REST::Admin::TransportResponse.new(
      status_code: 200,
      body: '{"commandResponse":[]}',
      headers: {}
    )
  end
end
```
