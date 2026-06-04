# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  add_filter %r{lib/mq/rest/admin/commands\.rb}
  enable_coverage :branch
  minimum_coverage line: 100, branch: 100
end

require 'minitest/autorun'
require 'mq/rest/admin'

module MQ
  module REST
    module Admin
      # Mock transport for testing. Records calls and returns canned responses.
      class MockTransport
        attr_reader :calls

        def initialize(responses: [])
          @responses = responses
          @call_index = 0
          @calls = []
        end

        def post_json(url, payload, headers:, timeout_seconds:)
          @calls << {
            url: url, payload: payload, headers: headers,
            timeout_seconds: timeout_seconds
          }
          if @call_index < @responses.length
            response = @responses[@call_index]
            @call_index += 1
            response
          else
            TransportResponse.new(status_code: 200, body: '{"commandResponse":[]}', headers: {})
          end
        end
      end

      # Helper to build a successful MQSC response body.
      def self.build_response(parameters_list = [], overall_cc: 0, overall_rc: 0)
        command_response = parameters_list.map do |params|
          { 'completionCode' => 0, 'reasonCode' => 0, 'parameters' => params }
        end
        JSON.generate({
                        'overallCompletionCode' => overall_cc,
                        'overallReasonCode' => overall_rc,
                        'commandResponse' => command_response
                      })
      end

      # Helper to build an error MQSC response body.
      def self.build_error_response(overall_cc: 2, overall_rc: 3008)
        JSON.generate({
                        'overallCompletionCode' => overall_cc,
                        'overallReasonCode' => overall_rc,
                        'commandResponse' => [
                          { 'completionCode' => overall_cc, 'reasonCode' => overall_rc }
                        ]
                      })
      end

      # Helper to create a test session with a mock transport.
      def self.build_test_session(responses: [], map_attributes: false, mapping_strict: false)
        transport = MockTransport.new(responses: responses)
        session = Session.new(
          'https://localhost:9443/ibmmq/rest/v2',
          'QM1',
          credentials: BasicAuth.new(username: 'admin', password: 'admin'),
          transport: transport,
          map_attributes: map_attributes,
          mapping_strict: mapping_strict
        )
        [session, transport]
      end
    end
  end
end
