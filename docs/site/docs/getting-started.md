# Getting Started

## Prerequisites

- **Ruby**: 3.2 or later
- **IBM MQ**: A running queue manager with the administrative REST API enabled

## Installation

Add to your Gemfile:

```ruby
gem 'mq-rest-admin'
```

Then run `bundle install`. Or install directly:

```bash
gem install mq-rest-admin
```

## Creating a session

All interaction with IBM MQ goes through a `Session`. You need the
REST API base URL, queue manager name, and credentials:

```ruby
require 'mq/rest/admin'

session = MQ::REST::Admin::Session.new(
  'https://localhost:9443/ibmmq/rest/v2',
  'QM1',
  credentials: MQ::REST::Admin::BasicAuth.new(
    username: 'mqadmin',
    password: 'mqadmin'
  ),
  # TLS is always verified. For a self-signed/dev queue manager, trust its
  # CA explicitly (nil uses the system trust store):
  tls_ca_file: ENV.fetch('MQ_REST_TLS_CA_FILE', nil)
)
```

## Running a command

Every MQSC command has a corresponding method on the session. Method names
follow the pattern `verb_qualifier` in snake_case:

```ruby
# DISPLAY QUEUE -- returns an array of hashes
queues = session.display_queue(name: '*')

queues.each do |queue|
  puts "#{queue['queue_name']} #{queue['current_queue_depth']}"
end
```

```ruby
# DISPLAY QMGR -- returns a single hash or nil
qmgr = session.display_qmgr

puts qmgr['queue_manager_name'] if qmgr
```

## Attribute mapping

By default, the session maps between developer-friendly `snake_case` names
and MQSC parameter names. This applies to both request and response attributes:

```ruby
# With mapping enabled (default)
queues = session.display_queue(
  name: 'MY.QUEUE',
  response_parameters: %w[current_queue_depth max_queue_depth]
)
# Returns: [{"queue_name" => "MY.QUEUE", "current_queue_depth" => 0, "max_queue_depth" => 5000}]

# With mapping disabled
session = MQ::REST::Admin::Session.new(
  'https://localhost:9443/ibmmq/rest/v2', 'QM1',
  credentials: MQ::REST::Admin::BasicAuth.new(username: 'mqadmin', password: 'mqadmin'),
  map_attributes: false
)
queues = session.display_queue(
  name: 'MY.QUEUE',
  response_parameters: %w[CURDEPTH MAXDEPTH]
)
# Returns: [{"QUEUE" => "MY.QUEUE", "CURDEPTH" => 0, "MAXDEPTH" => 5000}]
```

See [mapping pipeline](mapping-pipeline.md) for a detailed explanation of how
mapping works.

## Strict vs lenient mapping

By default, mapping runs in lenient mode. Unknown attribute names or values
pass through unchanged. In strict mode, unknown attributes raise an error:

```ruby
session = MQ::REST::Admin::Session.new(
  'https://localhost:9443/ibmmq/rest/v2', 'QM1',
  credentials: MQ::REST::Admin::BasicAuth.new(username: 'mqadmin', password: 'mqadmin'),
  mapping_strict: true
)
```

## Custom mapping overrides

Sites with existing naming conventions can override individual entries in the
built-in mapping tables without replacing them entirely. Pass override data
when creating the session:

```ruby
override_data = {
  'qualifiers' => {
    'queue' => {
      'response_key_map' => {
        'CURDEPTH' => 'queue_depth',      # override built-in mapping
        'MAXDEPTH' => 'queue_max_depth'    # override built-in mapping
      }
    }
  }
}

session = MQ::REST::Admin::Session.new(
  'https://localhost:9443/ibmmq/rest/v2', 'QM1',
  credentials: MQ::REST::Admin::BasicAuth.new(username: 'mqadmin', password: 'mqadmin'),
  mapping_overrides: override_data,
  mapping_overrides_mode: :merge
)

queues = session.display_queue(name: 'MY.QUEUE')
# Returns: [{"queue_depth" => 0, "queue_max_depth" => 5000, ...}]
```

Overrides are **sparse** -- you only specify the entries you want to change. All
other mappings in the qualifier continue to work as normal.

See [mapping pipeline](mapping-pipeline.md) for details on how each sub-map
is used.

## Gateway queue manager

The MQ REST API is available on all supported IBM MQ platforms (Linux, AIX,
Windows, z/OS, and IBM i). mq-rest-admin is developed and tested against the
**Linux** implementation only.

In enterprise environments, a **gateway queue manager** can route MQSC
commands to remote queue managers via MQ channels -- the same mechanism used
by `runmqsc -w` and the MQ Console.

To use a gateway, pass `gateway_qmgr` when creating the session. The
base URL and queue manager name specify the **target** (remote) queue manager,
while `gateway_qmgr` names the **local** queue manager whose REST API
routes the command:

```ruby
# Route commands to QM2 through QM1's REST API
session = MQ::REST::Admin::Session.new(
  'https://qm1-host:9443/ibmmq/rest/v2',
  'QM2',                                     # target queue manager
  credentials: MQ::REST::Admin::BasicAuth.new(username: 'mqadmin', password: 'mqadmin'),
  gateway_qmgr: 'QM1'                        # local gateway queue manager
)

qmgr = session.display_qmgr
# Returns QM2's queue manager attributes, routed through QM1
```

Prerequisites:

- The gateway queue manager must have a running REST API.
- MQ channels must be configured between the gateway and target queue managers.
- A QM alias (QREMOTE with empty RNAME) must map the target QM name to the
  correct transmission queue on the gateway.

## Error handling

`DISPLAY` commands return an empty array when no objects match. Queue manager
display methods return `nil` when no match is found. Non-display commands
raise a `CommandError` on failure:

```ruby
# Empty array -- no error
result = session.display_queue(name: 'NONEXISTENT.*')
# result == []

# Define raises error on failure
begin
  session.define_qlocal('MY.QUEUE')
rescue MQ::REST::Admin::CommandError => e
  puts e.message
  puts "HTTP status: #{e.status_code}"
  puts e.payload  # full MQ response payload
end
```

## Diagnostic state

The session retains the most recent request and response for inspection:

```ruby
session.display_queue(name: 'MY.QUEUE')

puts session.last_command_payload    # the Hash sent to MQ
puts session.last_response_payload   # the parsed Hash response
puts session.last_http_status        # HTTP status code
puts session.last_response_text      # raw response body
```
