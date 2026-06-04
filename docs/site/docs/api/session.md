# Session

## Overview

`MQ::REST::Admin::Session` is the main entry point for interacting with IBM MQ.
It holds connection details, authentication, mapping configuration, and
provides all command, ensure, and sync methods.

## Creating a session

```ruby
session = MQ::REST::Admin::Session.new(
  rest_base_url,
  qmgr_name,
  credentials:,
  gateway_qmgr: nil,
  tls_ca_file: nil,
  timeout_seconds: 30.0,
  map_attributes: true,
  mapping_strict: false,
  mapping_overrides: nil,
  mapping_overrides_mode: :merge,
  csrf_token: 'local',
  transport: nil
)
```

## Parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `rest_base_url` | `String` | (required) | IBM MQ REST API base URL |
| `qmgr_name` | `String` | (required) | Target queue manager name |
| `credentials` | Auth object | (required) | `BasicAuth`, `LTPAAuth`, or `CertificateAuth` |
| `gateway_qmgr` | `String` | `nil` | Gateway queue manager name for routing |
| `tls_ca_file` | `String` | `nil` | PEM CA bundle to trust for TLS (nil = system store); certificates are always verified |
| `timeout_seconds` | `Float` | `30.0` | HTTP request timeout |
| `map_attributes` | `Boolean` | `true` | Enable attribute mapping |
| `mapping_strict` | `Boolean` | `false` | Raise on unknown attributes |
| `mapping_overrides` | `Hash` | `nil` | Custom mapping data |
| `mapping_overrides_mode` | `Symbol` | `:merge` | `:merge` or `:replace` |
| `csrf_token` | `String` | `'local'` | CSRF token value |
| `transport` | Object | `nil` | Custom transport (uses `NetHTTPTransport` if nil) |

## Command methods

The session includes 148 command methods via the `Commands` module. See
[commands](commands.md) for the full list.

## Ensure methods

The session includes 16 ensure methods via the `Ensure` module. See
[ensure](ensure.md) for details.

## Sync methods

The session includes 9 sync methods via the `Sync` module. See
[sync](sync.md) for details.

## Diagnostic fields

After each command, the session retains:

| Field | Type | Description |
| --- | --- | --- |
| `last_command_payload` | `Hash` | The JSON payload sent to MQ |
| `last_response_payload` | `Hash` | The parsed JSON response |
| `last_http_status` | `Integer` | HTTP status code |
| `last_response_text` | `String` | Raw response body |
