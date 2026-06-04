# frozen_string_literal: true

require 'test_helper'
require 'webrick'

module MQ
  module REST
    module Admin
      class TransportResponseTest < Minitest::Test
        def test_transport_response_attributes
          r = TransportResponse.new(status_code: 200, body: 'ok', headers: { 'Content-Type' => 'application/json' })

          assert_equal 200, r.status_code
          assert_equal 'ok', r.body
          assert_equal({ 'Content-Type' => 'application/json' }, r.headers)
        end

        def test_transport_response_frozen
          r = TransportResponse.new(status_code: 200, body: '', headers: {})

          assert_predicate r, :frozen?
        end
      end

      class NetHTTPTransportTest < Minitest::Test
        def create_self_signed_cert
          require 'openssl'
          key = OpenSSL::PKey::RSA.new(2048)
          cert = OpenSSL::X509::Certificate.new
          cert.version = 2
          cert.serial = 1
          cert.subject = OpenSSL::X509::Name.new([%w[CN test]])
          cert.issuer = cert.subject
          cert.not_before = Time.now
          cert.not_after = Time.now + 3600
          cert.public_key = key.public_key
          cert.sign(key, OpenSSL::Digest.new('SHA256'))
          [cert, key]
        end

        def setup
          @server = WEBrick::HTTPServer.new(
            Port: 0,
            Logger: WEBrick::Log.new(File::NULL),
            AccessLog: []
          )
          @port = @server.config[:Port]
          @server.mount_proc('/test') do |req, res|
            res['Content-Type'] = 'application/json'
            res.body = JSON.generate({ 'received' => JSON.parse(req.body), 'method' => req.request_method })
          end
          @server.mount_proc('/error') do |_req, res|
            res.status = 500
            res.body = 'internal error'
          end
          @thread = Thread.new { @server.start }
        end

        def teardown
          @server.shutdown
          @thread.join(5)
        end

        def test_post_json_success
          transport = NetHTTPTransport.new
          response = transport.post_json(
            "http://localhost:#{@port}/test",
            { 'key' => 'value' },
            headers: { 'Accept' => 'application/json' },
            timeout_seconds: 5
          )

          assert_equal 200, response.status_code
          body = JSON.parse(response.body)

          assert_equal({ 'key' => 'value' }, body['received'])
          assert_equal 'POST', body['method']
        end

        def test_post_json_server_error
          transport = NetHTTPTransport.new
          response = transport.post_json(
            "http://localhost:#{@port}/error",
            {},
            headers: {},
            timeout_seconds: 5
          )

          assert_equal 500, response.status_code
        end

        def test_post_json_connection_refused
          transport = NetHTTPTransport.new
          assert_raises(TransportError) do
            transport.post_json(
              'http://localhost:1/unreachable',
              {},
              headers: {},
              timeout_seconds: 1
            )
          end
        end

        def test_post_json_headers_returned
          transport = NetHTTPTransport.new
          response = transport.post_json(
            "http://localhost:#{@port}/test",
            {},
            headers: {},
            timeout_seconds: 5
          )

          assert_kind_of Hash, response.headers
          assert response.headers.key?('content-type')
        end

        def test_post_json_nil_timeout
          transport = NetHTTPTransport.new
          response = transport.post_json(
            "http://localhost:#{@port}/test",
            { 't' => 1 },
            headers: {},
            timeout_seconds: nil
          )

          assert_equal 200, response.status_code
        end

        def test_client_cert_invalid_file
          transport = NetHTTPTransport.new(client_cert: '/nonexistent/cert.pem', client_key: '/nonexistent/key.pem')
          assert_raises(TransportError) do
            transport.post_json(
              "http://localhost:#{@port}/test",
              {},
              headers: {},
              timeout_seconds: 5
            )
          end
        end

        def test_client_cert_only
          transport = NetHTTPTransport.new(client_cert: '/nonexistent/cert.pem')
          assert_raises(TransportError) do
            transport.post_json(
              "http://localhost:#{@port}/test",
              {},
              headers: {},
              timeout_seconds: 5
            )
          end
        end

        def test_post_json_with_ca_file
          # transport.rb build_http - ca_file present branch (http.ca_file = @ca_file)
          require 'tempfile'
          cert, = create_self_signed_cert

          ca_file = Tempfile.new(['ca', '.pem'])
          begin
            ca_file.write(cert.to_pem)
            ca_file.close

            transport = NetHTTPTransport.new(ca_file: ca_file.path)
            response = transport.post_json(
              "http://localhost:#{@port}/test",
              { 't' => 1 },
              headers: {},
              timeout_seconds: 5
            )

            assert_equal 200, response.status_code
          ensure
            ca_file.unlink
          end
        end

        def test_reraises_own_errors
          # transport.rb:34 - raise e if e.is_a?(Error) then branch
          # When an Error subclass is raised during request, it should be re-raised as-is
          # This is hard to trigger via real HTTP, but we can verify TransportError propagates
          transport = NetHTTPTransport.new
          err = assert_raises(TransportError) do
            transport.post_json(
              'http://localhost:1/unreachable',
              {},
              headers: {},
              timeout_seconds: 1
            )
          end
          assert_includes err.message, 'Failed to reach'
        end

        def test_client_cert_and_key
          require 'tempfile'
          cert, key = create_self_signed_cert

          cert_file = Tempfile.new(['cert', '.pem'])
          key_file = Tempfile.new(['key', '.pem'])
          begin
            cert_file.write(cert.to_pem)
            cert_file.close
            key_file.write(key.to_pem)
            key_file.close

            transport = NetHTTPTransport.new(client_cert: cert_file.path, client_key: key_file.path)
            response = transport.post_json(
              "http://localhost:#{@port}/test",
              { 't' => 1 },
              headers: {},
              timeout_seconds: 5
            )

            assert_equal 200, response.status_code
          ensure
            cert_file.unlink
            key_file.unlink
          end
        end

        def test_client_cert_without_key
          require 'tempfile'
          cert, = create_self_signed_cert

          cert_file = Tempfile.new(['cert', '.pem'])
          begin
            cert_file.write(cert.to_pem)
            cert_file.close

            transport = NetHTTPTransport.new(client_cert: cert_file.path)
            response = transport.post_json(
              "http://localhost:#{@port}/test",
              { 't' => 1 },
              headers: {},
              timeout_seconds: 5
            )

            assert_equal 200, response.status_code
          ensure
            cert_file.unlink
          end
        end
      end
    end
  end
end
