# frozen_string_literal: true

require 'test_helper'

module MQ
  module REST
    module Admin
      class AuthTest < Minitest::Test
        def test_basic_auth_attributes
          auth = BasicAuth.new(username: 'user', password: 'pass')

          assert_equal 'user', auth.username
          assert_equal 'pass', auth.password
        end

        def test_basic_auth_frozen
          auth = BasicAuth.new(username: 'user', password: 'pass')

          assert_predicate auth, :frozen?
        end

        def test_ltpa_auth_attributes
          auth = LTPAAuth.new(username: 'user', password: 'pass')

          assert_equal 'user', auth.username
          assert_equal 'pass', auth.password
        end

        def test_certificate_auth_with_key
          auth = CertificateAuth.new(cert_path: '/path/cert.pem', key_path: '/path/key.pem')

          assert_equal '/path/cert.pem', auth.cert_path
          assert_equal '/path/key.pem', auth.key_path
        end

        def test_certificate_auth_without_key
          auth = CertificateAuth.new(cert_path: '/path/cert.pem')

          assert_equal '/path/cert.pem', auth.cert_path
          assert_nil auth.key_path
        end

        def test_perform_ltpa_login_success
          response = TransportResponse.new(
            status_code: 200, body: '{}',
            headers: { 'Set-Cookie' => 'LtpaToken2=abc123; Path=/; Secure' }
          )
          transport = MockTransport.new(responses: [response])
          cookie_name, token = Admin.perform_ltpa_login(
            transport, 'https://localhost:9443/ibmmq/rest/v2',
            LTPAAuth.new(username: 'user', password: 'pass'),
            csrf_token: 'local', timeout_seconds: 30.0
          )

          assert_equal 'LtpaToken2', cookie_name
          assert_equal 'abc123', token
          assert_equal 1, transport.calls.length
          assert_includes transport.calls[0][:url], '/login'
        end

        def test_perform_ltpa_login_success_with_suffixed_cookie
          response = TransportResponse.new(
            status_code: 200, body: '{}',
            headers: { 'Set-Cookie' => 'LtpaToken2_abcdef=suffixed_tok; Path=/; Secure' }
          )
          transport = MockTransport.new(responses: [response])
          cookie_name, token = Admin.perform_ltpa_login(
            transport, 'https://localhost:9443/ibmmq/rest/v2',
            LTPAAuth.new(username: 'user', password: 'pass'),
            csrf_token: 'local', timeout_seconds: 30.0
          )

          assert_equal 'LtpaToken2_abcdef', cookie_name
          assert_equal 'suffixed_tok', token
        end

        def test_perform_ltpa_login_failure_status
          response = TransportResponse.new(status_code: 401, body: '', headers: {})
          transport = MockTransport.new(responses: [response])
          err = assert_raises(AuthError) do
            Admin.perform_ltpa_login(
              transport, 'https://localhost:9443',
              LTPAAuth.new(username: 'user', password: 'pass'),
              csrf_token: nil, timeout_seconds: 30.0
            )
          end
          assert_includes err.message, 'LTPA login failed'
          assert_equal 401, err.status_code
        end

        def test_perform_ltpa_login_missing_token
          response = TransportResponse.new(status_code: 200, body: '{}', headers: {})
          transport = MockTransport.new(responses: [response])
          err = assert_raises(AuthError) do
            Admin.perform_ltpa_login(
              transport, 'https://localhost:9443',
              LTPAAuth.new(username: 'user', password: 'pass'),
              csrf_token: 'local', timeout_seconds: 30.0
            )
          end
          assert_includes err.message, 'no LtpaToken2 cookie'
        end

        def test_perform_ltpa_login_no_csrf_token
          response = TransportResponse.new(
            status_code: 200, body: '{}',
            headers: { 'Set-Cookie' => 'LtpaToken2=token123; Path=/' }
          )
          transport = MockTransport.new(responses: [response])
          cookie_name, token = Admin.perform_ltpa_login(
            transport, 'https://localhost:9443',
            LTPAAuth.new(username: 'u', password: 'p'),
            csrf_token: nil, timeout_seconds: nil
          )

          assert_equal 'LtpaToken2', cookie_name
          assert_equal 'token123', token
          refute transport.calls[0][:headers].key?('ibm-mq-rest-csrf-token')
        end

        def test_extract_ltpa_token_lowercase_header
          headers = { 'set-cookie' => 'LtpaToken2=abc; Path=/' }

          assert_equal %w[LtpaToken2 abc], Admin.extract_ltpa_token(headers)
        end

        def test_extract_ltpa_token_with_suffixed_cookie_name
          headers = { 'Set-Cookie' => 'LtpaToken2_xyz123=suffixed_tok; Path=/; Secure' }

          assert_equal %w[LtpaToken2_xyz123 suffixed_tok], Admin.extract_ltpa_token(headers)
        end

        def test_extract_ltpa_token_missing
          assert_nil Admin.extract_ltpa_token({})
        end

        def test_extract_ltpa_token_empty
          assert_nil Admin.extract_ltpa_token({ 'Set-Cookie' => '' })
        end

        def test_extract_ltpa_token_wrong_cookie
          headers = { 'Set-Cookie' => 'JSESSIONID=abc; Path=/' }

          assert_nil Admin.extract_ltpa_token(headers)
        end

        def test_extract_ltpa_token_nil_parts
          # A cookie string that when split by ";" returns nil first part
          # Actually, "".split(";").first returns "" not nil. Let's test with a trailing comma
          headers = { 'Set-Cookie' => 'LtpaToken2=tok;Path=/,;;' }

          assert_equal %w[LtpaToken2 tok], Admin.extract_ltpa_token(headers)
        end
      end
    end
  end
end
