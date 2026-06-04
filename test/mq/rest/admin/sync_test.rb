# frozen_string_literal: true

require 'test_helper'

module MQ
  module REST
    module Admin
      # Testable session subclass that stubs clock and sleep
      class TestableSession < Session
        attr_accessor :fake_time

        def initialize(...)
          super
          @fake_time = 0.0
        end

        private

        def clock_now
          @fake_time
        end

        def sleep_interval(_seconds)
          @fake_time += 0.1
        end
      end

      class SyncConfigTest < Minitest::Test
        def test_sync_config_defaults
          cfg = SyncConfig.new

          assert_in_delta 30.0, cfg.timeout_seconds
          assert_in_delta 1.0, cfg.poll_interval_seconds
        end

        def test_sync_config_custom
          cfg = SyncConfig.new(timeout_seconds: 60.0, poll_interval_seconds: 2.0)

          assert_in_delta 60.0, cfg.timeout_seconds
          assert_in_delta 2.0, cfg.poll_interval_seconds
        end

        def test_zero_timeout_raises
          err = assert_raises(ArgumentError) { SyncConfig.new(timeout_seconds: 0.0) }

          assert_match(/timeout_seconds must be positive/, err.message)
        end

        def test_negative_timeout_raises
          err = assert_raises(ArgumentError) { SyncConfig.new(timeout_seconds: -1.0) }

          assert_match(/timeout_seconds must be positive/, err.message)
        end

        def test_zero_poll_interval_raises
          err = assert_raises(ArgumentError) { SyncConfig.new(poll_interval_seconds: 0.0) }

          assert_match(/poll_interval_seconds must be positive/, err.message)
        end

        def test_negative_poll_interval_raises
          err = assert_raises(ArgumentError) { SyncConfig.new(poll_interval_seconds: -1.0) }

          assert_match(/poll_interval_seconds must be positive/, err.message)
        end
      end

      class SyncResultTest < Minitest::Test
        def test_sync_result_attributes
          r = SyncResult.new(operation: :started, polls: 3, elapsed_seconds: 4.5)

          assert_equal :started, r.operation
          assert_equal 3, r.polls
          assert_in_delta 4.5, r.elapsed_seconds
        end
      end

      class SyncTest < Minitest::Test
        def build_testable_session(responses:)
          transport = MockTransport.new(responses: responses)
          session = TestableSession.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          [session, transport]
        end

        def test_start_channel_sync_success
          start_body = Admin.build_response
          status_body = Admin.build_response([{ 'STATUS' => 'RUNNING' }])
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: start_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: status_body, headers: {})
                                            ])
          result = session.start_channel_sync('MY.CH', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :started, result.operation
          assert_equal 1, result.polls
        end

        def test_stop_channel_sync_empty_means_stopped
          stop_body = Admin.build_response
          empty_body = Admin.build_response
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: stop_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: empty_body, headers: {})
                                            ])
          result = session.stop_channel_sync('MY.CH', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :stopped, result.operation
        end

        def test_stop_channel_sync_status_stopped
          stop_body = Admin.build_response
          status_body = Admin.build_response([{ 'STATUS' => 'STOPPED' }])
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: stop_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: status_body, headers: {})
                                            ])
          result = session.stop_channel_sync('MY.CH', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :stopped, result.operation
        end

        def test_restart_channel
          stop_body = Admin.build_response
          stopped_body = Admin.build_response([{ 'STATUS' => 'STOPPED' }])
          start_body = Admin.build_response
          running_body = Admin.build_response([{ 'STATUS' => 'RUNNING' }])
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: stop_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: stopped_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: start_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: running_body, headers: {})
                                            ])
          result = session.restart_channel('MY.CH', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :restarted, result.operation
          assert_equal 2, result.polls
        end

        def test_start_channel_timeout
          start_body = Admin.build_response
          pending_body = Admin.build_response([{ 'STATUS' => 'STARTING' }])

          # Build enough responses to exceed timeout
          responses = [TransportResponse.new(status_code: 200, body: start_body, headers: {})]
          200.times do
            responses << TransportResponse.new(status_code: 200, body: pending_body, headers: {})
          end

          session, = build_testable_session(responses: responses)
          err = assert_raises(TimeoutError) do
            session.start_channel_sync('MY.CH', config: SyncConfig.new(timeout_seconds: 0.5))
          end
          assert_equal 'MY.CH', err.name
          assert_equal 'start', err.operation
        end

        def test_stop_channel_timeout
          stop_body = Admin.build_response
          running_body = Admin.build_response([{ 'STATUS' => 'RUNNING' }])

          responses = [TransportResponse.new(status_code: 200, body: stop_body, headers: {})]
          200.times do
            responses << TransportResponse.new(status_code: 200, body: running_body, headers: {})
          end

          session, = build_testable_session(responses: responses)
          err = assert_raises(TimeoutError) do
            session.stop_channel_sync('MY.CH', config: SyncConfig.new(timeout_seconds: 0.5))
          end
          assert_equal 'stop', err.operation
        end

        def test_start_listener_sync
          start_body = Admin.build_response
          status_body = Admin.build_response([{ 'status' => 'RUNNING' }])
          session, transport = build_testable_session(responses: [
                                                        TransportResponse.new(status_code: 200, body: start_body,
                                                                              headers: {}),
                                                        TransportResponse.new(status_code: 200, body: status_body,
                                                                              headers: {})
                                                      ])
          result = session.start_listener_sync('MY.LST', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :started, result.operation
          assert_equal 'LSSTATUS', transport.calls[1][:payload]['qualifier']
        end

        def test_stop_listener_sync
          stop_body = Admin.build_response
          status_body = Admin.build_response([{ 'STATUS' => 'STOPPED' }])
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: stop_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: status_body, headers: {})
                                            ])
          result = session.stop_listener_sync('MY.LST', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :stopped, result.operation
        end

        def test_restart_listener
          responses = [
            TransportResponse.new(status_code: 200, body: Admin.build_response, headers: {}),
            TransportResponse.new(status_code: 200,
                                  body: Admin.build_response([{ 'STATUS' => 'STOPPED' }]), headers: {}),
            TransportResponse.new(status_code: 200, body: Admin.build_response, headers: {}),
            TransportResponse.new(status_code: 200,
                                  body: Admin.build_response([{ 'status' => 'RUNNING' }]), headers: {})
          ]
          session, = build_testable_session(responses: responses)
          result = session.restart_listener('MY.LST', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :restarted, result.operation
        end

        def test_start_service_sync
          start_body = Admin.build_response
          status_body = Admin.build_response([{ 'STATUS' => 'RUNNING' }])
          session, transport = build_testable_session(responses: [
                                                        TransportResponse.new(status_code: 200, body: start_body,
                                                                              headers: {}),
                                                        TransportResponse.new(status_code: 200, body: status_body,
                                                                              headers: {})
                                                      ])
          result = session.start_service_sync('MY.SVC', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :started, result.operation
          assert_equal 'SVSTATUS', transport.calls[1][:payload]['qualifier']
        end

        def test_stop_service_sync
          stop_body = Admin.build_response
          status_body = Admin.build_response([{ 'STATUS' => 'STOPPED' }])
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: stop_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: status_body, headers: {})
                                            ])
          result = session.stop_service_sync('MY.SVC', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :stopped, result.operation
        end

        def test_restart_service
          responses = [
            TransportResponse.new(status_code: 200, body: Admin.build_response, headers: {}),
            TransportResponse.new(status_code: 200,
                                  body: Admin.build_response([{ 'STATUS' => 'STOPPED' }]), headers: {}),
            TransportResponse.new(status_code: 200, body: Admin.build_response, headers: {}),
            TransportResponse.new(status_code: 200,
                                  body: Admin.build_response([{ 'STATUS' => 'RUNNING' }]), headers: {})
          ]
          session, = build_testable_session(responses: responses)
          result = session.restart_service('MY.SVC', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :restarted, result.operation
        end

        def test_default_config
          start_body = Admin.build_response
          status_body = Admin.build_response([{ 'STATUS' => 'RUNNING' }])
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: start_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: status_body, headers: {})
                                            ])
          result = session.start_channel_sync('MY.CH')

          assert_equal :started, result.operation
        end

        def test_channel_status_key_channel_status
          start_body = Admin.build_response
          status_body = Admin.build_response([{ 'channel_status' => 'RUNNING' }])
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: start_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: status_body, headers: {})
                                            ])
          result = session.start_channel_sync('MY.CH', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :started, result.operation
        end

        def test_stop_listener_not_empty_means_stopped
          stop_body = Admin.build_response
          # Listener with empty response should NOT mean stopped (empty_means_stopped=false)
          pending_body = Admin.build_response([{ 'STATUS' => 'STOPPING' }])
          stopped_body = Admin.build_response([{ 'STATUS' => 'STOPPED' }])
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: stop_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: pending_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: stopped_body, headers: {})
                                            ])
          result = session.stop_listener_sync('MY.LST', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :stopped, result.operation
          assert_equal 2, result.polls
        end

        def test_lowercase_running_value
          start_body = Admin.build_response
          status_body = Admin.build_response([{ 'status' => 'running' }])
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: start_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: status_body, headers: {})
                                            ])
          result = session.start_listener_sync('MY.LST', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :started, result.operation
        end

        def test_lowercase_stopped_value
          stop_body = Admin.build_response
          status_body = Admin.build_response([{ 'status' => 'stopped' }])
          session, = build_testable_session(responses: [
                                              TransportResponse.new(status_code: 200, body: stop_body, headers: {}),
                                              TransportResponse.new(status_code: 200, body: status_body, headers: {})
                                            ])
          result = session.stop_listener_sync('MY.LST', config: SyncConfig.new(timeout_seconds: 10.0))

          assert_equal :stopped, result.operation
        end

        def test_base_clock_now
          # Test that the base Session clock_now works (uses Process.clock_gettime)
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          # Access private method to verify it returns a number
          time = session.send(:clock_now)

          assert_kind_of Float, time
          assert_operator time, :>, 0
        end

        def test_base_sleep_interval
          transport = MockTransport.new
          session = Session.new(
            'https://localhost:9443/ibmmq/rest/v2', 'QM1',
            credentials: BasicAuth.new(username: 'a', password: 'b'),
            transport: transport, map_attributes: false
          )
          # Call with 0 to verify it runs without error
          session.send(:sleep_interval, 0)
        end
      end
    end
  end
end
