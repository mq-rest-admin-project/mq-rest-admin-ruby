# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

module MQ
  module REST
    module Admin
      # Container for the raw HTTP response returned by a transport.
      #
      # @!attribute [r] status_code
      #   @return [Integer] the HTTP status code
      # @!attribute [r] body
      #   @return [String] the response body
      # @!attribute [r] headers
      #   @return [Hash{String => String}] the response headers
      TransportResponse = Data.define(:status_code, :body, :headers)

      # Default transport implementation using Net::HTTP.
      #
      # Implements the duck-type transport contract:
      # +#post_json(url, payload, headers:, timeout_seconds:)+
      class NetHTTPTransport
        # @param client_cert [String, nil] path to client certificate for mTLS
        # @param client_key [String, nil] path to client private key for mTLS
        # @param ca_file [String, nil] path to a PEM bundle of additional trusted
        #   CA certificates (for internal or self-signed CAs). When nil, the
        #   system trust store is used. TLS certificates are always verified.
        def initialize(client_cert: nil, client_key: nil, ca_file: nil)
          @client_cert = client_cert
          @client_key = client_key
          @ca_file = ca_file
        end

        # Send a JSON POST request and return the response.
        #
        # @param url [String] the target URL
        # @param payload [Hash{String => Object}] the JSON request body
        # @param headers [Hash{String => String}] additional HTTP headers
        # @param timeout_seconds [Float, nil] request timeout in seconds
        # @return [TransportResponse] the HTTP response
        # @raise [TransportError] if the request fails at the network level
        def post_json(url, payload, headers:, timeout_seconds:)
          uri = URI.parse(url)
          http = build_http(uri, timeout_seconds: timeout_seconds)
          request = build_request(uri, payload, headers)

          response = http.request(request)
          TransportResponse.new(
            status_code: response.code.to_i,
            body: response.body || '',
            headers: extract_headers(response)
          )
        rescue StandardError => e
          # :nocov:
          raise e if e.is_a?(Error)
          # :nocov:

          raise TransportError.new('Failed to reach MQ REST endpoint.', url: url)
        end

        private

        def build_http(uri, timeout_seconds:)
          http = Net::HTTP.new(uri.host, uri.port) # steep:ignore
          http.use_ssl = (uri.scheme == 'https')
          # TLS certificate verification is always enabled. To connect to a
          # server using an internal or self-signed CA, pass that CA via the
          # transport's ca_file (see Session tls_ca_file).
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.ca_file = @ca_file if @ca_file

          if timeout_seconds
            http.open_timeout = timeout_seconds
            http.read_timeout = timeout_seconds
            http.write_timeout = timeout_seconds
          end

          if @client_cert
            http.cert = OpenSSL::X509::Certificate.new(File.read(@client_cert))
            http.key = OpenSSL::PKey::RSA.new(File.read(@client_key)) if @client_key
          end

          http
        end

        def build_request(uri, payload, headers)
          request = Net::HTTP::Post.new(uri)
          request.content_type = 'application/json'
          headers.each { |key, value| request[key] = value }
          request.body = JSON.generate(payload)
          request
        end

        def extract_headers(response)
          result = {}
          response.each_header { |key, value| result[key] = value }
          result
        end
      end
    end
  end
end
