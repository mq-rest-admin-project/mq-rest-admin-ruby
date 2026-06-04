# frozen_string_literal: true

# Dead letter queue inspector.
#
# Checks the dead letter queue configuration for a queue manager,
# reports its depth and capacity, and suggests actions when messages
# are present.
#
# Usage:
#
#   ruby examples/dlq_inspector.rb

require 'mq/rest/admin'

module MQ
  module REST
    module Admin
      module Examples
        # Inspects dead letter queue configuration and depth.
        module DLQInspector
          CRITICAL_DEPTH_PCT = 90

          DLQReport = Data.define(
            :qmgr_name, :dlq_name, :configured, :current_depth, :max_depth,
            :depth_pct, :open_input, :open_output, :suggestion
          )

          def self.inspect_dlq(session)
            qmgr = session.display_qmgr

            dlq_name = ''
            dlq_name = qmgr['dead_letter_queue_name'].to_s.strip if qmgr

            if dlq_name.empty?
              return DLQReport.new(
                qmgr_name: session.qmgr_name, dlq_name: '', configured: false,
                current_depth: 0, max_depth: 0, depth_pct: 0.0,
                open_input: 0, open_output: 0,
                suggestion: 'No dead letter queue configured. Define one with ALTER QMGR DEADQ.'
              )
            end

            queues = session.display_queue(name: dlq_name)
            if queues.empty?
              return DLQReport.new(
                qmgr_name: session.qmgr_name, dlq_name: dlq_name, configured: true,
                current_depth: 0, max_depth: 0, depth_pct: 0.0,
                open_input: 0, open_output: 0,
                suggestion: "DLQ '#{dlq_name}' is configured but the queue does not exist."
              )
            end

            dlq = queues[0]
            current_depth = to_int(dlq['current_queue_depth'])
            max_depth = to_int(dlq['max_queue_depth'])
            open_input = to_int(dlq['open_input_count'])
            open_output = to_int(dlq['open_output_count'])
            depth_pct = max_depth.positive? ? (current_depth.to_f / max_depth * 100.0) : 0.0

            suggestion = if current_depth.zero?
                           'DLQ is empty. No action needed.'
                         elsif depth_pct >= CRITICAL_DEPTH_PCT
                           'DLQ is near capacity. Investigate and clear undeliverable messages urgently.'
                         elsif current_depth.positive?
                           'DLQ has messages. Investigate undeliverable messages.'
                         else
                           'DLQ is healthy.'
                         end

            DLQReport.new(
              qmgr_name: session.qmgr_name, dlq_name: dlq_name, configured: true,
              current_depth: current_depth, max_depth: max_depth, depth_pct: depth_pct,
              open_input: open_input, open_output: open_output, suggestion: suggestion
            )
          end

          def self.main(session)
            report = inspect_dlq(session)

            puts "\n=== Dead Letter Queue: #{report.qmgr_name} ==="
            puts "  Configured: #{report.configured}"
            puts "  DLQ name:   #{report.dlq_name.empty? ? '(none)' : report.dlq_name}"

            if report.configured && !report.dlq_name.empty?
              printf "  Depth:      %d / %d (%.1f%%)\n", # rubocop:disable Style/FormatStringToken
                     report.current_depth, report.max_depth, report.depth_pct
              puts "  Input:      #{report.open_input}"
              puts "  Output:     #{report.open_output}"
            end

            puts "  Suggestion: #{report.suggestion}"

            report
          end

          def self.to_int(value)
            return value if value.is_a?(Integer)

            Integer(value.to_s)
          rescue ArgumentError, TypeError
            0
          end

          private_class_method :to_int
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  session = MQ::REST::Admin::Session.new(
    ENV.fetch('MQ_REST_BASE_URL', 'https://localhost:9473/ibmmq/rest/v2'),
    ENV.fetch('MQ_QMGR_NAME', 'QM1'),
    credentials: MQ::REST::Admin::BasicAuth.new(
      username: ENV.fetch('MQ_ADMIN_USER', 'mqadmin'),
      password: ENV.fetch('MQ_ADMIN_PASSWORD', 'mqadmin')
    ),
    tls_ca_file: ENV.fetch('MQ_REST_TLS_CA_FILE', nil)
  )

  MQ::REST::Admin::Examples::DLQInspector.main(session)
end
