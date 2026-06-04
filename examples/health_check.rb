# frozen_string_literal: true

# Queue manager health check.
#
# Connects to one or more queue managers and checks QMGR status,
# command server availability, and listener state. Produces a
# pass/fail summary for each queue manager.
#
# Usage:
#
#   ruby examples/health_check.rb
#
# Set MQ_REST_BASE_URL_QM2 to also check QM2.

require 'mq/rest/admin'

module MQ
  module REST
    module Admin
      module Examples
        # Checks queue manager health: QMGR status, command server, and listeners.
        module HealthCheck
          ListenerResult = Data.define(:name, :status)

          QMHealthResult = Data.define(
            :qmgr_name, :reachable, :status, :command_server, :listeners, :passed
          )

          def self.check_health(session)
            qmgr = fetch_qmgr(session)
            return unreachable_result(session.qmgr_name) unless qmgr

            qmgr_name = extract_qmgr_name(qmgr, session.qmgr_name)
            status = extract_status(session)
            command_server = extract_command_server(session)
            listeners = fetch_listeners(session)

            QMHealthResult.new(
              qmgr_name: qmgr_name, reachable: true, status: status,
              command_server: command_server, listeners: listeners,
              passed: status != 'UNKNOWN'
            )
          end

          def self.main(sessions)
            results = []
            sessions.each do |session|
              result = check_health(session)
              results << result
              print_result(result)
            end
            results
          end

          def self.fetch_qmgr(session)
            session.display_qmgr
          rescue MQ::REST::Admin::Error
            nil
          end

          def self.unreachable_result(qmgr_name)
            QMHealthResult.new(
              qmgr_name: qmgr_name, reachable: false, status: 'UNKNOWN',
              command_server: 'UNKNOWN', listeners: [], passed: false
            )
          end

          def self.extract_qmgr_name(qmgr, default)
            name = qmgr&.[]('queue_manager_name')
            name.is_a?(String) && !name.strip.empty? ? name.strip : default
          end

          def self.extract_status(session)
            qmstatus = session.display_qmstatus
            ha = qmstatus&.[]('ha_status')
            ha ? ha.to_s.strip : 'UNKNOWN'
          end

          def self.extract_command_server(session)
            cmdserv = session.display_cmdserv
            cs = cmdserv&.[]('status')
            cs ? cs.to_s.strip : 'UNKNOWN'
          end

          def self.fetch_listeners(session)
            raw = session.display_listener('*')
            raw.map do |listener|
              ListenerResult.new(
                name: listener['listener_name'].to_s.strip,
                status: listener['start_mode'].to_s.strip
              )
            end
          rescue MQ::REST::Admin::Error
            []
          end

          def self.print_result(result)
            verdict = result.passed ? 'PASS' : 'FAIL'
            puts "\n=== #{result.qmgr_name}: #{verdict} ==="
            puts "  Reachable:      #{result.reachable}"
            puts "  Status:         #{result.status}"
            puts "  Command server: #{result.command_server}"
            puts "  Listeners:      #{result.listeners.length}"
            result.listeners.each do |listener|
              puts "    #{listener.name}: #{listener.status}"
            end
          end

          private_class_method :fetch_qmgr, :unreachable_result, :extract_qmgr_name,
                               :extract_status, :extract_command_server, :fetch_listeners,
                               :print_result
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  sessions = []

  sessions << MQ::REST::Admin::Session.new(
    ENV.fetch('MQ_REST_BASE_URL', 'https://localhost:9473/ibmmq/rest/v2'),
    ENV.fetch('MQ_QMGR_NAME', 'QM1'),
    credentials: MQ::REST::Admin::BasicAuth.new(
      username: ENV.fetch('MQ_ADMIN_USER', 'mqadmin'),
      password: ENV.fetch('MQ_ADMIN_PASSWORD', 'mqadmin')
    ),
    tls_ca_file: ENV.fetch('MQ_REST_TLS_CA_FILE', nil)
  )

  qm2_url = ENV.fetch('MQ_REST_BASE_URL_QM2', nil)
  if qm2_url
    sessions << MQ::REST::Admin::Session.new(
      qm2_url, 'QM2',
      credentials: MQ::REST::Admin::BasicAuth.new(
        username: ENV.fetch('MQ_ADMIN_USER', 'mqadmin'),
        password: ENV.fetch('MQ_ADMIN_PASSWORD', 'mqadmin')
      ),
      tls_ca_file: ENV.fetch('MQ_REST_TLS_CA_FILE', nil)
    )
  end

  MQ::REST::Admin::Examples::HealthCheck.main(sessions)
end
