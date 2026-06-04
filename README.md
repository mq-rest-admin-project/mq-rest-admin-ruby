# mq-rest-admin-ruby

Ruby wrapper for the IBM MQ administrative REST API.

`mq-rest-admin` provides typed Ruby methods for every MQSC command
exposed by the IBM MQ 9.4 `runCommandJSON` REST endpoint. Attribute names are
automatically translated between Ruby idioms and native MQSC parameter
names.

## Table of Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Documentation](#documentation)
- [Development](#development)
- [License](#license)

## Installation

```bash
gem install mq-rest-admin
```

Requires Ruby 3.2+.

## Quick start

```ruby
require "mq/rest/admin"

session = MQ::REST::Admin::Session.new(
  "https://localhost:9443/ibmmq/rest/v2",
  "QM1",
  credentials: MQ::REST::Admin::BasicAuth.new(username: "mqadmin", password: "mqadmin")
  # TLS is always verified. For a self-signed/dev queue manager, pass
  # tls_ca_file: "/path/to/dev-ca.pem"
)

# Display queue manager attributes
qmgr = session.display_qmgr
puts qmgr

# List all queues
queues = session.display_queue
queues.each { |q| puts q["queue_name"] }
```

## Documentation

Full documentation: <https://mq-rest-admin-project.github.io/mq-rest-admin-ruby/>

## Development

```bash
bundle install
bundle exec rake test
bundle exec rubocop
```

## License

GPL-3.0-or-later. See `LICENSE`.
