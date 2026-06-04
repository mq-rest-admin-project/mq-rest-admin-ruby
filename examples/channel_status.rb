# frozen_string_literal: true

# Channel status report.
#
# Displays channel definitions alongside live channel status, identifies
# channels that are defined but not running, and shows connection details.
#
# Usage:
#
#   ruby examples/channel_status.rb

require 'mq/rest/admin'

module MQ
  module REST
    module Admin
      module Examples
        # Reports channel definitions alongside live status.
        module ChannelStatus
          ChannelInfo = Data.define(:name, :channel_type, :connection_name, :defined, :status)

          def self.report_channel_status(session)
            definitions = fetch_definitions(session)
            live_status = fetch_live_status(session)

            results = build_defined_channels(definitions, live_status)
            append_undefined_channels(results, definitions, live_status)
            results
          end

          def self.main(session)
            results = report_channel_status(session)

            printf "\n%-30s %-12s %-25s %-8s %s\n", # rubocop:disable Style/FormatStringToken
                   'Channel', 'Type', 'Connection', 'Defined', 'Status'
            puts '-' * 90

            results.each do |info|
              printf "%-30s %-12s %-25s %-8s %s\n", # rubocop:disable Style/FormatStringToken
                     info.name, info.channel_type, info.connection_name,
                     info.defined ? 'Yes' : 'No', info.status
            end

            inactive = results.select { |c| c.defined && c.status == 'INACTIVE' }
            puts "\nDefined but inactive: #{inactive.map(&:name).join(', ')}" unless inactive.empty?

            results
          end

          def self.fetch_definitions(session)
            channels = session.display_channel(name: '*')
            defs = {}
            channels.each do |channel|
              cname = channel['channel_name'].to_s.strip
              defs[cname] = channel unless cname.empty?
            end
            defs
          end

          def self.fetch_live_status(session)
            status = {}
            statuses = session.display_chstatus('*')
            statuses.each do |entry|
              cname = entry['channel_name'].to_s.strip
              cstatus = entry['status'].to_s.strip
              status[cname] = cstatus unless cname.empty?
            end
            status
          rescue MQ::REST::Admin::Error
            {}
          end

          def self.build_defined_channels(definitions, live_status)
            definitions.sort.map do |cname, defn|
              ChannelInfo.new(
                name: cname,
                channel_type: defn['channel_type'].to_s.strip,
                connection_name: defn['connection_name'].to_s.strip,
                defined: true,
                status: live_status.fetch(cname, 'INACTIVE')
              )
            end
          end

          def self.append_undefined_channels(results, definitions, live_status)
            live_status.sort.each do |cname, cstatus|
              next if definitions.key?(cname)

              results << ChannelInfo.new(
                name: cname, channel_type: '', connection_name: '',
                defined: false, status: cstatus
              )
            end
          end

          private_class_method :fetch_definitions, :fetch_live_status,
                               :build_defined_channels, :append_undefined_channels
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

  MQ::REST::Admin::Examples::ChannelStatus.main(session)
end
