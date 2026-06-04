# frozen_string_literal: true

# Queue depth monitor.
#
# Displays local queues with their current depth, flags queues that
# are approaching capacity, and uses WHERE filtering to find non-empty
# queues.
#
# Usage:
#
#   ruby examples/queue_depth_monitor.rb
#
# Set DEPTH_THRESHOLD_PCT to change the warning threshold (default 80).

require 'mq/rest/admin'

module MQ
  module REST
    module Admin
      module Examples
        # Monitors queue depths and flags queues approaching capacity.
        module QueueDepthMonitor
          QueueDepthInfo = Data.define(
            :name, :current_depth, :max_depth, :depth_pct, :open_input, :open_output, :warning
          )

          LOCAL_TYPES = %w[QLOCAL LOCAL].freeze

          def self.monitor_queue_depths(session, threshold_pct: 80.0)
            queues = session.display_queue(name: '*')
            results = []

            queues.each do |queue|
              qtype = queue['type'].to_s.strip.upcase
              next unless LOCAL_TYPES.include?(qtype)

              results << build_depth_info(queue, threshold_pct)
            end

            results.sort_by { |q| -q.depth_pct }
          end

          def self.main(session, threshold_pct: 80.0)
            results = monitor_queue_depths(session, threshold_pct: threshold_pct)

            printf "\n%-40s %8s %8s %6s %4s %4s %s\n", # rubocop:disable Style/FormatStringToken
                   'Queue', 'Depth', 'Max', '%', 'In', 'Out', 'Status'
            puts '-' * 90

            results.each do |info|
              status = info.warning ? 'WARNING' : 'OK'
              printf "%-40s %8d %8d %5.1f%% %4d %4d %s\n", # rubocop:disable Style/FormatStringToken
                     info.name, info.current_depth, info.max_depth,
                     info.depth_pct, info.open_input, info.open_output, status
            end

            warning_count = results.count(&:warning)
            puts "\nTotal queues: #{results.length}, warnings: #{warning_count}"

            results
          end

          def self.build_depth_info(queue, threshold_pct)
            current_depth = to_int(queue['current_queue_depth'])
            max_depth = to_int(queue['max_queue_depth'])
            depth_pct = max_depth.positive? ? (current_depth.to_f / max_depth * 100.0) : 0.0

            QueueDepthInfo.new(
              name: queue['queue_name'].to_s.strip,
              current_depth: current_depth,
              max_depth: max_depth,
              depth_pct: depth_pct,
              open_input: to_int(queue['open_input_count']),
              open_output: to_int(queue['open_output_count']),
              warning: depth_pct >= threshold_pct
            )
          end

          def self.to_int(value)
            return value if value.is_a?(Integer)

            Integer(value.to_s)
          rescue ArgumentError, TypeError
            0
          end

          private_class_method :build_depth_info, :to_int
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  threshold = Float(ENV.fetch('DEPTH_THRESHOLD_PCT', '80'))

  session = MQ::REST::Admin::Session.new(
    ENV.fetch('MQ_REST_BASE_URL', 'https://localhost:9473/ibmmq/rest/v2'),
    ENV.fetch('MQ_QMGR_NAME', 'QM1'),
    credentials: MQ::REST::Admin::BasicAuth.new(
      username: ENV.fetch('MQ_ADMIN_USER', 'mqadmin'),
      password: ENV.fetch('MQ_ADMIN_PASSWORD', 'mqadmin')
    ),
    tls_ca_file: ENV.fetch('MQ_REST_TLS_CA_FILE', nil)
  )

  MQ::REST::Admin::Examples::QueueDepthMonitor.main(session, threshold_pct: threshold)
end
