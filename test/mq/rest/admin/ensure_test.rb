# frozen_string_literal: true

require 'test_helper'

module MQ
  module REST
    module Admin
      class EnsureResultTest < Minitest::Test
        def test_ensure_result_defaults
          r = EnsureResult.new(action: :created)

          assert_equal :created, r.action
          assert_empty r.changed
        end

        def test_ensure_result_with_changed
          r = EnsureResult.new(action: :updated, changed: %w[a b])

          assert_equal :updated, r.action
          assert_equal %w[a b], r.changed
        end

        def test_ensure_result_frozen
          r = EnsureResult.new(action: :unchanged)

          assert_predicate r, :frozen?
          assert_predicate r.changed, :frozen?
        end
      end

      class EnsureTest < Minitest::Test
        def test_ensure_qlocal_creates
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, transport = Admin.build_test_session(responses: [
                                                          TransportResponse.new(status_code: 200, body: error_body,
                                                                                headers: {}),
                                                          TransportResponse.new(status_code: 200, body: create_body,
                                                                                headers: {})
                                                        ])
          result = session.ensure_qlocal('MY.Q', request_parameters: { 'MAXDEPTH' => '5000' })

          assert_equal :created, result.action
          assert_equal 2, transport.calls.length
          assert_equal 'DISPLAY', transport.calls[0][:payload]['command']
          assert_equal 'DEFINE', transport.calls[1][:payload]['command']
          assert_equal 'QLOCAL', transport.calls[1][:payload]['qualifier']
        end

        def test_ensure_qlocal_unchanged
          display_body = Admin.build_response([{ 'MAXDEPTH' => '5000' }])
          session, transport = Admin.build_test_session(responses: [
                                                          TransportResponse.new(status_code: 200, body: display_body,
                                                                                headers: {})
                                                        ])
          result = session.ensure_qlocal('MY.Q', request_parameters: { 'MAXDEPTH' => '5000' })

          assert_equal :unchanged, result.action
          assert_equal 1, transport.calls.length
        end

        def test_ensure_qlocal_updates
          display_body = Admin.build_response([{ 'MAXDEPTH' => '3000' }])
          alter_body = Admin.build_response
          session, transport = Admin.build_test_session(responses: [
                                                          TransportResponse.new(status_code: 200, body: display_body,
                                                                                headers: {}),
                                                          TransportResponse.new(status_code: 200, body: alter_body,
                                                                                headers: {})
                                                        ])
          result = session.ensure_qlocal('MY.Q', request_parameters: { 'MAXDEPTH' => '5000' })

          assert_equal :updated, result.action
          assert_includes result.changed, 'MAXDEPTH'
          assert_equal 'ALTER', transport.calls[1][:payload]['command']
        end

        def test_ensure_qlocal_no_params
          display_body = Admin.build_response([{ 'DESCR' => 'test' }])
          session, transport = Admin.build_test_session(responses: [
                                                          TransportResponse.new(status_code: 200, body: display_body,
                                                                                headers: {})
                                                        ])
          result = session.ensure_qlocal('MY.Q')

          assert_equal :unchanged, result.action
          assert_equal 1, transport.calls.length
        end

        def test_ensure_qlocal_creates_with_no_params
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_qlocal('MY.Q')

          assert_equal :created, result.action
        end

        def test_ensure_qmgr_unchanged
          display_body = Admin.build_response([{ 'DESCR' => 'test' }])
          session, transport = Admin.build_test_session(responses: [
                                                          TransportResponse.new(status_code: 200, body: display_body,
                                                                                headers: {})
                                                        ])
          result = session.ensure_qmgr(request_parameters: { 'DESCR' => 'test' })

          assert_equal :unchanged, result.action
          assert_equal 1, transport.calls.length
        end

        def test_ensure_qmgr_updates
          display_body = Admin.build_response([{ 'DESCR' => 'old' }])
          alter_body = Admin.build_response
          session, transport = Admin.build_test_session(responses: [
                                                          TransportResponse.new(status_code: 200, body: display_body,
                                                                                headers: {}),
                                                          TransportResponse.new(status_code: 200, body: alter_body,
                                                                                headers: {})
                                                        ])
          result = session.ensure_qmgr(request_parameters: { 'DESCR' => 'new' })

          assert_equal :updated, result.action
          assert_includes result.changed, 'DESCR'
          assert_equal 2, transport.calls.length
        end

        def test_ensure_qmgr_no_params
          result_session, = Admin.build_test_session
          result = result_session.ensure_qmgr

          assert_equal :unchanged, result.action
        end

        def test_ensure_qmgr_empty_response
          display_body = Admin.build_response
          alter_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: display_body,
                                                                      headers: {}),
                                                TransportResponse.new(status_code: 200, body: alter_body, headers: {})
                                              ])
          result = session.ensure_qmgr(request_parameters: { 'DESCR' => 'new' })

          assert_equal :updated, result.action
        end

        def test_ensure_case_insensitive_match
          display_body = Admin.build_response([{ 'DESCR' => 'Test Queue' }])
          session, transport = Admin.build_test_session(responses: [
                                                          TransportResponse.new(status_code: 200, body: display_body,
                                                                                headers: {})
                                                        ])
          result = session.ensure_qlocal('MY.Q', request_parameters: { 'DESCR' => 'test queue' })

          assert_equal :unchanged, result.action
          assert_equal 1, transport.calls.length
        end

        def test_ensure_nil_current_value_triggers_update
          display_body = Admin.build_response([{}])
          alter_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: display_body,
                                                                      headers: {}),
                                                TransportResponse.new(status_code: 200, body: alter_body, headers: {})
                                              ])
          result = session.ensure_qlocal('MY.Q', request_parameters: { 'DESCR' => 'new' })

          assert_equal :updated, result.action
        end

        # Test all 16 ensure methods exist
        def test_all_ensure_methods_exist
          ensure_methods = %i[
            ensure_qmgr ensure_qlocal ensure_qremote ensure_qalias ensure_qmodel
            ensure_channel ensure_authinfo ensure_listener ensure_namelist
            ensure_process ensure_service ensure_topic ensure_sub
            ensure_stgclass ensure_comminfo ensure_cfstruct
          ]

          ensure_methods.each do |method|
            assert_respond_to Session.new(
              'https://localhost:9443/ibmmq/rest/v2', 'QM1',
              credentials: BasicAuth.new(username: 'a', password: 'b'),
              transport: MockTransport.new, map_attributes: false
            ), method, "Session should respond to #{method}"
          end
        end

        def test_ensure_channel_creates
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, transport = Admin.build_test_session(responses: [
                                                          TransportResponse.new(status_code: 200, body: error_body,
                                                                                headers: {}),
                                                          TransportResponse.new(status_code: 200, body: create_body,
                                                                                headers: {})
                                                        ])
          result = session.ensure_channel('MY.CH')

          assert_equal :created, result.action
          assert_equal 'CHANNEL', transport.calls[0][:payload]['qualifier']
          assert_equal 'CHANNEL', transport.calls[1][:payload]['qualifier']
        end

        # Cover all remaining ensure_* delegate methods
        def test_ensure_qremote
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, transport = Admin.build_test_session(responses: [
                                                          TransportResponse.new(status_code: 200, body: error_body,
                                                                                headers: {}),
                                                          TransportResponse.new(status_code: 200, body: create_body,
                                                                                headers: {})
                                                        ])
          result = session.ensure_qremote('MY.Q')

          assert_equal :created, result.action
          assert_equal 'QREMOTE', transport.calls[1][:payload]['qualifier']
        end

        def test_ensure_qalias
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_qalias('MY.Q')

          assert_equal :created, result.action
        end

        def test_ensure_qmodel
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_qmodel('MY.Q')

          assert_equal :created, result.action
        end

        def test_ensure_authinfo
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_authinfo('MY.AI')

          assert_equal :created, result.action
        end

        def test_ensure_listener
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_listener('MY.LST')

          assert_equal :created, result.action
        end

        def test_ensure_namelist
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_namelist('MY.NL')

          assert_equal :created, result.action
        end

        def test_ensure_process
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_process('MY.PRC')

          assert_equal :created, result.action
        end

        def test_ensure_service
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_service('MY.SVC')

          assert_equal :created, result.action
        end

        def test_ensure_topic
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_topic('MY.T')

          assert_equal :created, result.action
        end

        def test_ensure_sub
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_sub('MY.SUB')

          assert_equal :created, result.action
        end

        def test_ensure_stgclass
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_stgclass('MY.STG')

          assert_equal :created, result.action
        end

        def test_ensure_comminfo
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_comminfo('MY.CI')

          assert_equal :created, result.action
        end

        def test_ensure_cfstruct
          error_body = Admin.build_error_response
          create_body = Admin.build_response
          session, = Admin.build_test_session(responses: [
                                                TransportResponse.new(status_code: 200, body: error_body, headers: {}),
                                                TransportResponse.new(status_code: 200, body: create_body, headers: {})
                                              ])
          result = session.ensure_cfstruct('MY.CF')

          assert_equal :created, result.action
        end
      end
    end
  end
end
