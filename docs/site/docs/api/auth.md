# Authentication

## Overview

mq-rest-admin supports three authentication modes. All are immutable value
objects created with `Data.define` (Ruby 3.3+).

## CertificateAuth (mTLS)

Mutual TLS authentication using client certificates. The MQ REST API
authenticates the client via the TLS handshake -- no credentials are sent
in the HTTP request.

```ruby
auth = MQ::REST::Admin::CertificateAuth.new(
  cert_path: '/path/to/client.pem',
  key_path: '/path/to/client.key'   # optional if cert contains the key
)
```

| Field | Type | Description |
| --- | --- | --- |
| `cert_path` | `String` | Path to client certificate PEM file |
| `key_path` | `String` or `nil` | Path to client key PEM file |

When `key_path` is nil, the certificate file is expected to contain both the
certificate and private key.

## LTPAAuth

LTPA token-based authentication. The session performs a login request to
obtain an LTPA token cookie, which is then sent with every subsequent request.

```ruby
auth = MQ::REST::Admin::LTPAAuth.new(
  username: 'mqadmin',
  password: 'mqadmin'
)
```

| Field | Type | Description |
| --- | --- | --- |
| `username` | `String` | Login username |
| `password` | `String` | Login password |

The LTPA login is performed automatically on the first command. The token is
extracted from the `Set-Cookie` response header.

## BasicAuth

HTTP Basic authentication. Credentials are base64-encoded and sent in the
`Authorization` header with every request.

```ruby
auth = MQ::REST::Admin::BasicAuth.new(
  username: 'mqadmin',
  password: 'mqadmin'
)
```

| Field | Type | Description |
| --- | --- | --- |
| `username` | `String` | HTTP Basic username |
| `password` | `String` | HTTP Basic password |

## Choosing an authentication mode

- **CertificateAuth**: Preferred for production. No credentials in transit.
- **LTPAAuth**: Good for environments with LDAP/Active Directory integration.
  Token is cached after login.
- **BasicAuth**: Simplest option. Credentials sent with every request.
  Suitable for development and testing.
