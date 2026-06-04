# frozen_string_literal: true

# Queue status and connection handle report.
#
# Demonstrates DISPLAY QSTATUS TYPE(HANDLE) and DISPLAY CONN
# TYPE(HANDLE) queries, showing how mq-rest-admin transparently flattens
# the nested objects response structure into uniform flat hashes.
#
# Usage:
#
#   ruby examples/queue_status.rb

require 'mq/rest/admin'

module MQ
  module REST
    module Admin
      module Examples
        # Reports queue status handles and connection handles.
        module QueueStatus
          QueueHandleInfo = Data.define(:queue_name, :handle_state, :connection_id, :open_options)
          ConnectionHandleInfo = Data.define(:connection_id, :object_name, :handle_state, :object_type)

          def self.report_queue_handles(session)
            entries = session.display_qstatus(
              '*', request_parameters: { 'type' => 'HANDLE' }
            )

            entries.map do |entry|
              QueueHandleInfo.new(
                queue_name: entry['queue_name'].to_s.strip,
                handle_state: entry['handle_state'].to_s.strip,
                connection_id: entry['connection_id'].to_s.strip,
                open_options: entry['open_options'].to_s.strip
              )
            end
          rescue MQ::REST::Admin::Error
            []
          end

          def self.report_connection_handles(session)
            entries = session.display_conn(
              '*', request_parameters: { 'connection_info_type' => 'HANDLE' }
            )

            entries.map do |entry|
              ConnectionHandleInfo.new(
                connection_id: entry['connection_id'].to_s.strip,
                object_name: entry['object_name'].to_s.strip,
                handle_state: entry['handle_state'].to_s.strip,
                object_type: entry['object_type'].to_s.strip
              )
            end
          rescue MQ::REST::Admin::Error
            []
          end

          def self.main(session)
            queue_handles = report_queue_handles(session)

            printf "\n%-30s %-15s %-30s %s\n", # rubocop:disable Style/FormatStringToken
                   'Queue', 'Handle State', 'Connection ID', 'Open Options'
            puts '-' * 90
            queue_handles.each do |info|
              printf "%-30s %-15s %-30s %s\n", # rubocop:disable Style/FormatStringToken
                     info.queue_name, info.handle_state, info.connection_id, info.open_options
            end
            puts '  (no active queue handles)' if queue_handles.empty?

            conn_handles = report_connection_handles(session)

            printf "\n%-30s %-30s %-15s %s\n", # rubocop:disable Style/FormatStringToken
                   'Connection ID', 'Object Name', 'Handle State', 'Object Type'
            puts '-' * 90
            conn_handles.each do |info|
              printf "%-30s %-30s %-15s %s\n", # rubocop:disable Style/FormatStringToken
                     info.connection_id, info.object_name, info.handle_state, info.object_type
            end
            puts '  (no active connection handles)' if conn_handles.empty?
          end
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

  MQ::REST::Admin::Examples::QueueStatus.main(session)
end
