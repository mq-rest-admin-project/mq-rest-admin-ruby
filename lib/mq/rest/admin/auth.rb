# frozen_string_literal: true

require 'cgi'

module MQ
  module REST
    # Authentication types and LTPA login support.
    module Admin
      # HTTP Basic authentication credentials.
      #
      # @example
      #   creds = BasicAuth.new(username: "admin", password: "secret")
      BasicAuth = Data.define(:username, :password)

      # LTPA token-based authentication credentials.
      #
      # The session performs an LTPA login at construction time and uses
      # the returned LtpaToken2 cookie for subsequent requests.
      #
      # @example
      #   creds = LTPAAuth.new(username: "admin", password: "secret")
      LTPAAuth = Data.define(:username, :password)

      # Mutual TLS (mTLS) client certificate authentication.
      #
      # The client certificate is configured on the transport layer.
      # No Authorization header is sent.
      #
      # @example
      #   creds = CertificateAuth.new(cert_path: "/path/to/cert.pem")
      CertificateAuth = Data.define(:cert_path, :key_path) do
        # @param cert_path [String] path to the client certificate file
        # @param key_path [String, nil] path to the private key file
        def initialize(cert_path:, key_path: nil)
          super
        end
      end

      # @return [String] the LTPA cookie name used for token-based authentication
      LTPA_COOKIE_NAME = 'LtpaToken2'

      # @return [String] the REST API login path for LTPA authentication
      LTPA_LOGIN_PATH = '/login'

      module_function

      # Perform an LTPA login and return the cookie name and token value.
      #
      # @param transport [NetHTTPTransport] the HTTP transport to use
      # @param rest_base_url [String] the MQ REST API base URL
      # @param credentials [LTPAAuth] the LTPA credentials
      # @param csrf_token [String, nil] the CSRF token to include
      # @param timeout_seconds [Float] request timeout in seconds
      # @return [Array(String, String)] a [cookie_name, token_value] pair
      # @raise [AuthError] if login fails or no token is returned
      def perform_ltpa_login(transport, rest_base_url, credentials, csrf_token:, timeout_seconds:)
        login_url = "#{rest_base_url}#{LTPA_LOGIN_PATH}"
        headers = { 'Accept' => 'application/json' }
        headers['ibm-mq-rest-csrf-token'] = csrf_token unless csrf_token.nil?
        payload = { 'username' => credentials.username, 'password' => credentials.password }

        response = transport.post_json(
          login_url, payload,
          headers: headers, timeout_seconds: timeout_seconds
        )

        if response.status_code >= 400
          raise AuthError.new(
            'LTPA login failed.',
            url: login_url, status_code: response.status_code
          )
        end

        result = extract_ltpa_token(response.headers)
        if result.nil?
          raise AuthError.new(
            'LTPA login succeeded but no LtpaToken2 cookie was returned.',
            url: login_url, status_code: response.status_code
          )
        end

        result
      end

      # Extract an LtpaToken2 cookie from HTTP response headers.
      #
      # Matches any cookie whose name equals "LtpaToken2" or starts with
      # "LtpaToken2" (e.g. "LtpaToken2_abcdef"), using prefix matching
      # to support Liberty's suffixed cookie names.
      #
      # @param headers [Hash{String => String}] the HTTP response headers
      # @return [Array(String, String), nil] a [cookie_name, token_value] pair, or nil if not found
      def extract_ltpa_token(headers)
        set_cookie = headers['Set-Cookie'] || headers['set-cookie']
        return nil if set_cookie.nil? || set_cookie.empty?

        # Parse Set-Cookie header for LtpaToken2 (exact or prefixed)
        set_cookie.split(',').each do |cookie_str|
          parts = cookie_str.strip.split(';').first
          # :nocov:
          next if parts.nil?
          # :nocov:

          name, _, value = parts.partition('=')
          return [name.strip, value] if name.strip.start_with?(LTPA_COOKIE_NAME)
        end
        nil
      end
    end
  end
end
