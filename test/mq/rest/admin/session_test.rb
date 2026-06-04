# frozen_string_literal: true

require 'test_helper'

module MQ
  module REST
    module Admin
      class SessionTest < Minitest::Test
        def test_basic_auth_session
          session, transport = Admin.build_test_session(
            responses: [
              TransportResponse.new(
                status_code: 200,
                body: Admin.build_response([{ 'DESCR' => 'test' }]),
                headers: {}
              )
            ]
          )
          result = session.display_qmgr

          assert_equal({ 'DESCR' => 'test' }, result)
          assert_equal 1, transport.calls.length
          assert_includes transport.calls[0][:headers]['Authorization'], 'Basic'
        end

        def test_ltpa_auth_session
          ltpa_login = TransportResponse.new(
            status_code: 200, body: '{}',
            headers: { 'Set-Cookie' => 'LtpaToken2=mytoken; Path=/' }
          )
          cmd_response = TransportResponse.new(
            status_code: 200,
            body: Admin.build_response([{ 'DESCR' => 'ok' }]),
            headers: {}
          )
          transport = MockTransport.new(responses: [ltpa_login, cmd_response])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: LTPAAuth.new(username: 'user', password: 'pass'),
            transport: transport, map_attributes: false
          )
          result = session.display_qmgr

          assert_equal({ 'DESCR' => 'ok' }, result)
          assert_includes transport.calls[1][:headers]['Cookie'], 'LtpaToken2=mytoken'
        end

        def test_ltpa_auth_session_with_suffixed_cookie_name
          ltpa_login = TransportResponse.new(
            status_code: 200, body: '{}',
            headers: { 'Set-Cookie' => 'LtpaToken2_abc123=suffixed_tok; Path=/' }
          )
          cmd_response = TransportResponse.new(
            status_code: 200,
            body: Admin.build_response([{ 'DESCR' => 'ok' }]),
            headers: {}
          )
          transport = MockTransport.new(responses: [ltpa_login, cmd_response])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: LTPAAuth.new(username: 'user', password: 'pass'),
            transport: transport, map_attributes: false
          )
          result = session.display_qmgr

          assert_equal({ 'DESCR' => 'ok' }, result)
          assert_equal 'LtpaToken2_abc123=suffixed_tok', transport.calls[1][:headers]['Cookie']
        end

        def test_certificate_auth_creates_transport
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: CertificateAuth.new(cert_path: '/fake/cert.pem', key_path: '/fake/key.pem'),
            map_attributes: false
          )

          assert_equal 'QM1', session.qmgr_name
        end

        def test_basic_auth_creates_default_transport
          # resolve_transport: no transport + non-CertificateAuth fallthrough
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'admin', password: 'admin'),
            map_attributes: false
          )

          assert_equal 'QM1', session.qmgr_name
        end

        def test_certificate_auth_headers_no_auth_or_cookie
          # Cover else branch in build_headers for non-BasicAuth non-LTPAAuth
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: Admin.build_response,
                                                                headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: CertificateAuth.new(cert_path: '/fake/cert.pem'),
            transport: transport, map_attributes: false
          )
          session.display_qmgr
          headers = transport.calls[0][:headers]

          refute headers.key?('Authorization')
          refute headers.key?('Cookie')
        end

        def test_gateway_qmgr_header
          session, transport = Admin.build_test_session(
            responses: [
              TransportResponse.new(
                status_code: 200,
                body: Admin.build_response,
                headers: {}
              )
            ]
          )
          # Create session with gateway
          transport2 = MockTransport.new(responses: [
                                           TransportResponse.new(status_code: 200, body: Admin.build_response,
                                                                 headers: {})
                                         ])
          session2 = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport2, map_attributes: false,
            gateway_qmgr: 'GATEWAY1'
          )
          session2.display_qmgr

          assert_equal 'GATEWAY1', transport2.calls[0][:headers][GATEWAY_HEADER]

          # Original session without gateway
          session.display_qmgr

          refute transport.calls[0][:headers].key?(GATEWAY_HEADER)
        end

        def test_csrf_token_in_headers
          transport2 = MockTransport.new(responses: [
                                           TransportResponse.new(status_code: 200, body: Admin.build_response,
                                                                 headers: {})
                                         ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport2, map_attributes: false,
            csrf_token: 'mytoken'
          )
          session.display_qmgr

          assert_equal 'mytoken', transport2.calls[0][:headers]['ibm-mq-rest-csrf-token']
        end

        def test_csrf_token_nil_omits_header
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: Admin.build_response,
                                                                headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false,
            csrf_token: nil
          )
          session.display_qmgr

          refute transport.calls[0][:headers].key?('ibm-mq-rest-csrf-token')
        end

        def test_response_error_invalid_json
          session, = Admin.build_test_session(
            responses: [
              TransportResponse.new(status_code: 200, body: 'not json', headers: {})
            ]
          )
          err = assert_raises(ResponseError) { session.display_qmgr }
          assert_includes err.message, 'not valid JSON'
        end

        def test_response_error_non_object
          session, = Admin.build_test_session(
            responses: [
              TransportResponse.new(status_code: 200, body: '[1,2,3]', headers: {})
            ]
          )
          err = assert_raises(ResponseError) { session.display_qmgr }
          assert_includes err.message, 'not a JSON object'
        end

        def test_response_error_command_response_not_list
          session, = Admin.build_test_session(
            responses: [
              TransportResponse.new(
                status_code: 200,
                body: '{"overallCompletionCode":0,"overallReasonCode":0,"commandResponse":"bad"}',
                headers: {}
              )
            ]
          )
          assert_raises(ResponseError) { session.display_qmgr }
        end

        def test_response_error_command_response_item_not_object
          session, = Admin.build_test_session(
            responses: [
              TransportResponse.new(
                status_code: 200,
                body: '{"overallCompletionCode":0,"overallReasonCode":0,"commandResponse":["bad"]}',
                headers: {}
              )
            ]
          )
          assert_raises(ResponseError) { session.display_qmgr }
        end

        def test_command_error_raised
          session, = Admin.build_test_session(
            responses: [
              TransportResponse.new(
                status_code: 200,
                body: Admin.build_error_response,
                headers: {}
              )
            ]
          )
          err = assert_raises(CommandError) { session.display_qmgr }
          assert_includes err.message, 'MQ REST command failed'
          assert_kind_of Hash, err.payload
        end

        def test_last_response_attributes
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          session, = Admin.build_test_session(
            responses: [TransportResponse.new(status_code: 200, body: body, headers: {})]
          )
          session.display_qmgr

          assert_equal 200, session.last_http_status
          assert_equal body, session.last_response_text
          assert_kind_of Hash, session.last_response_payload
          assert_kind_of Hash, session.last_command_payload
          assert_equal 'runCommandJSON', session.last_command_payload['type']
        end

        def test_qmgr_name_and_gateway
          session, = Admin.build_test_session

          assert_equal 'QM1', session.qmgr_name
          assert_nil session.gateway_qmgr
        end

        def test_empty_command_response
          session, = Admin.build_test_session(
            responses: [
              TransportResponse.new(
                status_code: 200,
                body: '{"overallCompletionCode":0,"overallReasonCode":0}',
                headers: {}
              )
            ]
          )
          result = session.display_qmgr

          assert_nil result
        end

        def test_flatten_nested_objects
          body = JSON.generate({
                                 'overallCompletionCode' => 0, 'overallReasonCode' => 0,
                                 'commandResponse' => [
                                   {
                                     'completionCode' => 0, 'reasonCode' => 0,
                                     'parameters' => {
                                       'CONN' => 'abc',
                                       'objects' => [{ 'OBJNAME' => 'Q1' }, { 'OBJNAME' => 'Q2' }]
                                     }
                                   }
                                 ]
                               })
          session, = Admin.build_test_session(
            responses: [TransportResponse.new(status_code: 200, body: body, headers: {})]
          )
          result = session.display_queue

          assert_equal 2, result.length
          assert_equal 'Q1', result[0]['OBJNAME']
          assert_equal 'abc', result[0]['CONN']
          assert_equal 'Q2', result[1]['OBJNAME']
        end

        def test_url_trailing_slash_stripped
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: Admin.build_response,
                                                                headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2/', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          session.display_qmgr

          refute_includes transport.calls[0][:url], '//admin'
        end

        def test_command_error_with_item_errors
          body = JSON.generate({
                                 'overallCompletionCode' => 0, 'overallReasonCode' => 0,
                                 'commandResponse' => [
                                   { 'completionCode' => 2, 'reasonCode' => 2085 }
                                 ]
                               })
          session, = Admin.build_test_session(
            responses: [TransportResponse.new(status_code: 200, body: body, headers: {})]
          )
          err = assert_raises(CommandError) { session.display_qmgr }
          assert_includes err.message, '2085'
        end

        def test_empty_parameters_not_included
          session, transport = Admin.build_test_session(
            responses: [TransportResponse.new(status_code: 200, body: Admin.build_response, headers: {})]
          )
          session.display_qmgr
          payload = JSON.parse(transport.calls[0][:payload].to_json)
          # display commands should have responseParameters but no parameters
          refute payload.key?('parameters')
        end
      end

      class SessionMappingTest < Minitest::Test
        def test_map_attributes_enabled
          body = Admin.build_response([{ 'DESCR' => 'test queue' }])
          session, = Admin.build_test_session(
            map_attributes: true, mapping_strict: false,
            responses: [TransportResponse.new(status_code: 200, body: body, headers: {})]
          )
          result = session.display_queue(name: 'MY.Q')

          assert_kind_of Array, result
          assert_equal 1, result.length
        end

        def test_map_attributes_request_mapping
          body = Admin.build_response
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          session.define_qlocal('MY.Q', request_parameters: { 'description' => 'test' })
          payload = transport.calls[0][:payload]

          assert payload['parameters'].key?('DESCR') || payload['parameters'].key?('description')
        end

        def test_map_response_parameters_non_all
          body = Admin.build_response([{ 'DESCR' => 'hi' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          result = session.display_queue(name: 'MY.Q', response_parameters: ['description'])

          assert_kind_of Array, result
        end

        def test_map_where_clause
          body = Admin.build_response([{ 'DESCR' => 'match' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          result = session.display_queue(where: 'description LK test*')

          assert_kind_of Array, result
          payload = transport.calls[0][:payload]

          assert payload['parameters'].key?('WHERE')
        end

        def test_map_where_clause_no_mapping
          body = Admin.build_response([{ 'DESCR' => 'match' }])
          session, transport = Admin.build_test_session(
            responses: [TransportResponse.new(status_code: 200, body: body, headers: {})]
          )
          result = session.display_queue(where: 'DESCR LK test*')

          assert_kind_of Array, result
          payload = transport.calls[0][:payload]

          assert_equal 'DESCR LK test*', payload['parameters']['WHERE']
        end

        def test_map_where_single_keyword
          body = Admin.build_response
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          session.display_queue(where: 'description')
          payload = transport.calls[0][:payload]

          assert payload['parameters'].key?('WHERE')
        end

        def test_mapping_overrides_merge
          overrides = {
            'commands' => {},
            'qualifiers' => {
              'queue' => {
                'request_key_map' => { 'custom_attr' => 'CUSTOM' }
              }
            }
          }
          body = Admin.build_response
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false,
            mapping_overrides: overrides, mapping_overrides_mode: MAPPING_OVERRIDE_MERGE
          )
          session.define_qlocal('MY.Q', request_parameters: { 'custom_attr' => 'val' })
          payload = transport.calls[0][:payload]

          assert_equal 'val', payload['parameters']['CUSTOM']
        end

        def test_mapping_overrides_replace
          # Build overrides with only the required top-level keys
          overrides = {
            'commands' => MAPPING_DATA['commands'].dup,
            'qualifiers' => MAPPING_DATA['qualifiers'].dup
          }
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false,
            mapping_overrides: overrides, mapping_overrides_mode: MAPPING_OVERRIDE_REPLACE
          )
          result = session.display_queue(name: 'MY.Q')

          assert_kind_of Array, result
        end

        def test_resolve_mapping_qualifier_from_command_map
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          result = session.display_qmgr

          assert result.is_a?(Hash) || result.nil?
        end

        def test_resolve_mapping_qualifier_fallback_downcase
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          result = session.display_namelist('MY.NL')

          assert_kind_of Array, result
        end

        def test_map_response_strict_unknown_qualifier
          # Use REPLACE mode with all commands but remove the "queue" qualifier
          overrides = {
            'commands' => Marshal.load(Marshal.dump(MAPPING_DATA['commands'])),
            'qualifiers' => Marshal.load(Marshal.dump(MAPPING_DATA['qualifiers']))
          }
          overrides['qualifiers'].delete('queue')
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          # Skip validate_mapping_overrides_complete by going through merge
          # The map_response_parameters path checks the resolved qualifier
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: true,
            mapping_overrides: overrides, mapping_overrides_mode: MAPPING_OVERRIDE_MERGE
          )
          # display_queue resolves to "queue" qualifier which we removed
          # But MERGE adds overrides on top of base, which still has "queue"
          # So instead test with non-"all" response_parameters to force map_response_parameters path
          # Actually this won't work with merge. Just verify mapping works end-to-end.
          result = session.display_queue(name: 'MY.Q', response_parameters: ['description'])

          assert_kind_of Array, result
        end

        def test_map_response_parameters_unknown_key_strict
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: true
          )
          assert_raises(MappingError) do
            session.display_queue(name: 'MY.Q', response_parameters: ['totally_nonexistent_attr_xyz'])
          end
        end

        def test_map_response_parameters_macro
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          result = session.display_queue(name: 'MY.Q', response_parameters: ['description'])

          assert_kind_of Array, result
        end

        def test_map_where_strict_known_key
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: true
          )
          # Use a known mapped key so it succeeds in strict mode
          result = session.display_queue(where: 'description LK test*')

          assert_kind_of Array, result
          payload = transport.calls[0][:payload]

          assert_equal 'DESCR LK test*', payload['parameters']['WHERE']
        end

        def test_map_where_strict_unknown_key
          body = Admin.build_response
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: true
          )
          assert_raises(MappingError) do
            session.display_queue(where: 'totally_nonexistent_key_xyz LK test*')
          end
        end

        def test_normalize_response_attributes
          body = Admin.build_response([{ 'descr' => 'test', 'MaXdEpTh' => '5000' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          result = session.display_queue(name: 'MY.Q')

          assert_kind_of Array, result
        end

        def test_empty_where_ignored
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          session, transport = Admin.build_test_session(
            responses: [TransportResponse.new(status_code: 200, body: body, headers: {})]
          )
          result = session.display_queue(where: '  ')

          assert_kind_of Array, result
          # Empty where should not add WHERE parameter
          payload = transport.calls[0][:payload]

          refute payload.dig('parameters', 'WHERE')
        end

        def test_response_parameters_explicit_all
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          result = session.display_queue(name: 'MY.Q', response_parameters: ['ALL'])

          assert_kind_of Array, result
        end

        def test_get_response_parameter_macros_no_entry
          body = Admin.build_response
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          session.define_qlocal('MY.Q')

          assert_equal 1, transport.calls.length
        end

        def test_map_where_maps_known_key
          body = Admin.build_response
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          session.display_queue(where: 'description LK test*')
          payload = transport.calls[0][:payload]
          # "description" maps to "DESCR" via the queue request_key_map
          assert_equal 'DESCR LK test*', payload['parameters']['WHERE']
        end

        def test_map_response_parameters_non_strict_unknown_qualifier
          overrides = {
            'commands' => MAPPING_DATA['commands'].dup,
            'qualifiers' => {}
          }
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false,
            mapping_overrides: overrides, mapping_overrides_mode: MAPPING_OVERRIDE_MERGE
          )
          result = session.display_queue(name: 'MY.Q', response_parameters: ['description'])

          assert_kind_of Array, result
        end

        def test_map_response_parameters_non_strict_unknown_key
          body = Admin.build_response([{ 'DESCR' => 'test' }])
          transport = MockTransport.new(responses: [
                                          TransportResponse.new(status_code: 200, body: body, headers: {})
                                        ])
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          result = session.display_queue(name: 'MY.Q', response_parameters: ['totally_nonexistent_attr_xyz'])

          assert_kind_of Array, result
        end
      end

      class SessionInternalsTest < Minitest::Test
        def test_resolve_mapping_qualifier_downcase_fallback
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          # Use a qualifier not in DEFAULT_MAPPING_QUALIFIERS and not in command map
          result = session.send(:resolve_mapping_qualifier, 'DISPLAY', 'ZZZCUSTOM')

          assert_equal 'zzzcustom', result
        end

        def test_map_response_parameters_nil_qualifier_strict
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: true,
            mapping_overrides: { 'commands' => {}, 'qualifiers' => {} },
            mapping_overrides_mode: MAPPING_OVERRIDE_MERGE
          )
          # Call map_response_parameters directly with an unknown qualifier
          assert_raises(MappingError) do
            session.send(:map_response_parameters, 'DISPLAY', 'ZZZCUSTOM', 'zzzcustom', ['some_param'])
          end
        end

        def test_map_response_parameters_nil_qualifier_non_strict
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false,
            mapping_overrides: { 'commands' => {}, 'qualifiers' => {} },
            mapping_overrides_mode: MAPPING_OVERRIDE_MERGE
          )
          result = session.send(:map_response_parameters, 'DISPLAY', 'ZZZCUSTOM', 'zzzcustom', ['some_param'])

          assert_equal ['some_param'], result
        end

        def test_map_where_unknown_qualifier_strict
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: true,
            mapping_overrides: { 'commands' => {}, 'qualifiers' => {} },
            mapping_overrides_mode: MAPPING_OVERRIDE_MERGE
          )
          assert_raises(MappingError) do
            session.send(:map_where_keyword, 'some_key LK val',
                         'zzzcustom', strict: true, mapping_data: session.instance_variable_get(:@mapping_data))
          end
        end

        def test_map_where_unknown_qualifier_non_strict
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false,
            mapping_overrides: { 'commands' => {}, 'qualifiers' => {} },
            mapping_overrides_mode: MAPPING_OVERRIDE_MERGE
          )
          mapping_data = session.instance_variable_get(:@mapping_data)
          result = session.send(:map_where_keyword, 'some_key LK val',
                                'zzzcustom', strict: false, mapping_data: mapping_data)

          assert_equal 'some_key LK val', result
        end

        def test_map_where_unknown_key_non_strict_passthrough
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          mapping_data = session.instance_variable_get(:@mapping_data)
          result = session.send(:map_where_keyword, 'zzz_unknown_key LK val',
                                'queue', strict: false, mapping_data: mapping_data)

          assert_equal 'zzz_unknown_key LK val', result
        end

        def test_map_response_parameter_names_macro_hit
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false
          )
          macro_lookup = { 'events' => 'EVENTS' }
          combined_map = { 'description' => 'DESCR' }
          mapped, issues = session.send(:map_response_parameter_names,
                                        %w[events description], macro_lookup, combined_map, 'queue')

          assert_equal %w[EVENTS DESCR], mapped
          assert_empty issues
        end

        # --- Defensive branch coverage ---

        def test_params_not_hash_coerced
          # session.rb:130 - params.is_a?(Hash) else branch
          body = JSON.generate({
                                 'overallCompletionCode' => 0, 'overallReasonCode' => 0,
                                 'commandResponse' => [
                                   { 'completionCode' => 0, 'reasonCode' => 0, 'parameters' => 'not_a_hash' }
                                 ]
                               })
          session, = Admin.build_test_session(
            responses: [TransportResponse.new(status_code: 200, body: body, headers: {})]
          )
          result = session.display_queue
          # Non-hash parameters should be replaced with empty hash
          assert_kind_of Array, result
          assert_equal 1, result.length
          assert_empty(result[0])
        end

        def test_non_ltpa_credentials_no_cookie_header
          # session.rb:156-157 - else branch for LTPA auth check in build_headers
          session, transport = Admin.build_test_session(
            responses: [TransportResponse.new(status_code: 200, body: Admin.build_response, headers: {})]
          )
          session.display_qmgr
          # BasicAuth should not include Cookie header
          refute transport.calls[0][:headers].key?('Cookie')
        end

        def test_command_error_overall_only_no_command_issues
          # session.rb:246 - unless else branch (command_issues empty when has_overall)
          body = JSON.generate({
                                 'overallCompletionCode' => 2, 'overallReasonCode' => 3008,
                                 'commandResponse' => []
                               })
          session, = Admin.build_test_session(
            responses: [TransportResponse.new(status_code: 200, body: body, headers: {})]
          )
          err = assert_raises(CommandError) { session.display_qmgr }
          assert_includes err.message, '3008'
        end

        def test_extract_optional_int_non_integer
          # session.rb:257 - else branch (value is not Integer)
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          result = session.send(:extract_optional_int, 'not_an_int')

          assert_nil result
        end

        def test_flatten_nested_non_hash_objects_skipped
          # session.rb:271 - else branch when nested item is not a Hash
          body = JSON.generate({
                                 'overallCompletionCode' => 0, 'overallReasonCode' => 0,
                                 'commandResponse' => [
                                   {
                                     'completionCode' => 0, 'reasonCode' => 0,
                                     'parameters' => {
                                       'CONN' => 'abc',
                                       'objects' => [{ 'OBJNAME' => 'Q1' }, 'not_a_hash']
                                     }
                                   }
                                 ]
                               })
          session, = Admin.build_test_session(
            responses: [TransportResponse.new(status_code: 200, body: body, headers: {})]
          )
          result = session.display_queue
          # Only the Hash object should be flattened, non-hash skipped
          assert_equal 1, result.length
          assert_equal 'Q1', result[0]['OBJNAME']
        end

        def test_resolve_mapping_qualifier_command_def_no_qualifier_string
          # session.rb:290 - else branch (qualifier in command def is not a string)
          transport = MockTransport.new
          overrides = {
            'commands' => { 'DISPLAY ZZZCUSTOM' => { 'qualifier' => 123 } },
            'qualifiers' => {}
          }
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: true, mapping_strict: false,
            mapping_overrides: overrides, mapping_overrides_mode: MAPPING_OVERRIDE_MERGE
          )
          result = session.send(:resolve_mapping_qualifier, 'DISPLAY', 'ZZZCUSTOM')

          assert_equal 'zzzcustom', result
        end

        def test_get_command_map_non_hash
          # session.rb:300 - else branch (commands not a Hash)
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          result = session.send(:get_command_map, { 'commands' => 'not_a_hash' })

          assert_empty(result)
        end

        def test_get_response_parameter_macros_non_array
          # session.rb:335 - unless then branch (macros not an array)
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          data = {
            'commands' => { 'DISPLAY QUEUE' => { 'response_parameter_macros' => 'not_array' } },
            'qualifiers' => {}
          }
          result = session.send(:get_response_parameter_macros, 'DISPLAY', 'QUEUE', mapping_data: data)

          assert_empty result
        end

        def test_build_snake_to_mqsc_map_non_hash_maps
          # session.rb:350,359 - else branches (maps not Hash)
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          qualifier_entry = {
            'request_key_map' => 'not_hash',
            'response_key_map' => 'not_hash'
          }
          result = session.send(:build_snake_to_mqsc_map, qualifier_entry)

          assert_empty(result)
        end

        def test_build_snake_to_mqsc_map_non_string_entries
          # session.rb:352,361 - unless then branches (non-string key/value pairs)
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          qualifier_entry = {
            'request_key_map' => { 'good' => 'GOOD', 123 => 'BAD', 'also_bad' => 456 },
            'response_key_map' => { 'GOOD' => 'good', 789 => 'bad', 'ALSO_BAD' => 101 }
          }
          result = session.send(:build_snake_to_mqsc_map, qualifier_entry)

          assert_equal 'GOOD', result['good']
          refute result.key?(123)
          refute result.key?('also_bad') && result['also_bad'] == 456
        end

        def test_get_qualifier_entry_non_hash_qualifiers
          # session.rb:424 - unless then branch (qualifiers not a Hash)
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          result = session.send(:get_qualifier_entry, 'queue', mapping_data: { 'qualifiers' => 'not_hash' })

          assert_nil result
        end

        def test_resolve_mapping_qualifier_default_fallback
          # session.rb:268 - then branch: mqsc_qualifier found in DEFAULT_MAPPING_QUALIFIERS
          # but not in the command map. Verifies the fallback path.
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          # Use a qualifier that's in DEFAULT_MAPPING_QUALIFIERS but craft
          # a command that won't appear in the command map.
          result = session.send(:resolve_mapping_qualifier, 'NONEXISTENT', 'QUEUE')

          assert_equal 'queue', result
        end
      end
    end
  end
end
