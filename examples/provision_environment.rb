# frozen_string_literal: true

# Environment provisioner.
#
# Defines a complete set of queues, channels, and remote queue
# definitions across two queue managers, then verifies connectivity.
# Includes a teardown function to remove all provisioned objects.
#
# Usage:
#
#   ruby examples/provision_environment.rb
#
# Requires both QM1 and QM2 to be running. Set MQ_REST_BASE_URL_QM2
# to the QM2 REST endpoint (default: https://localhost:9474/ibmmq/rest/v2).

require 'mq/rest/admin'

module MQ
  module REST
    module Admin
      module Examples
        # Provisions cross-QM objects and verifies connectivity.
        module ProvisionEnvironment
          PREFIX = 'PROV'

          ProvisionResult = Data.define(:objects_created, :objects_failed, :verified)

          def self.provision(qm1, qm2)
            tracker = ObjectTracker.new

            provision_local_queues(tracker, qm1, qm2)
            provision_xmit_queues(tracker, qm1, qm2)
            provision_remote_queues(tracker, qm1, qm2)
            provision_channels(tracker, qm1, qm2)

            verified = verify_objects(qm1, qm2)

            ProvisionResult.new(
              objects_created: tracker.created, objects_failed: tracker.failed, verified: verified
            )
          end

          def self.teardown(qm1, qm2)
            failures = []

            [[qm1, 'QM1'], [qm2, 'QM2']].each do |session, label|
              ["#{PREFIX}.QM1.TO.QM2", "#{PREFIX}.QM2.TO.QM1"].each do |channel|
                delete_object(failures, session, :delete_channel, channel, label)
              end

              [
                "#{PREFIX}.REMOTE.TO.QM1", "#{PREFIX}.REMOTE.TO.QM2",
                "#{PREFIX}.QM1.TO.QM2.XMITQ", "#{PREFIX}.QM2.TO.QM1.XMITQ",
                "#{PREFIX}.QM1.LOCAL", "#{PREFIX}.QM2.LOCAL"
              ].each do |queue|
                delete_object(failures, session, :delete_queue, queue, label)
              end
            end

            failures
          end

          def self.main(qm1, qm2)
            puts "\n=== Provisioning environment ==="
            result = provision(qm1, qm2)

            puts "\nCreated: #{result.objects_created.length}"
            result.objects_created.each { |obj| puts "  + #{obj}" }

            unless result.objects_failed.empty?
              puts "\nFailed: #{result.objects_failed.length}"
              result.objects_failed.each { |obj| puts "  ! #{obj}" }
            end

            puts "\nVerified: #{result.verified}"

            puts "\n=== Tearing down ==="
            failures = teardown(qm1, qm2)
            if failures.empty?
              puts 'Teardown complete.'
            else
              puts "Teardown failures: #{failures}"
            end

            result
          end

          # Tracks created and failed objects during provisioning.
          class ObjectTracker
            attr_reader :created, :failed

            def initialize
              @created = []
              @failed = []
            end

            def define(session, method_name, name, parameters)
              label = "#{session.qmgr_name}/#{name}"
              session.send(method_name, name, request_parameters: parameters)
              @created << label
            rescue MQ::REST::Admin::Error
              @failed << label
            end
          end

          def self.provision_local_queues(tracker, qm1, qm2)
            tracker.define(qm1, :define_qlocal, "#{PREFIX}.QM1.LOCAL",
                           { 'replace' => 'yes', 'default_persistence' => 'yes',
                             'description' => 'provisioned local queue on QM1' })
            tracker.define(qm2, :define_qlocal, "#{PREFIX}.QM2.LOCAL",
                           { 'replace' => 'yes', 'default_persistence' => 'yes',
                             'description' => 'provisioned local queue on QM2' })
          end

          def self.provision_xmit_queues(tracker, qm1, qm2)
            tracker.define(qm1, :define_qlocal, "#{PREFIX}.QM1.TO.QM2.XMITQ",
                           { 'replace' => 'yes', 'usage' => 'XMITQ',
                             'description' => 'xmit queue QM1 to QM2' })
            tracker.define(qm2, :define_qlocal, "#{PREFIX}.QM2.TO.QM1.XMITQ",
                           { 'replace' => 'yes', 'usage' => 'XMITQ',
                             'description' => 'xmit queue QM2 to QM1' })
          end

          def self.provision_remote_queues(tracker, qm1, qm2)
            tracker.define(qm1, :define_qremote, "#{PREFIX}.REMOTE.TO.QM2",
                           { 'replace' => 'yes', 'remote_queue_name' => "#{PREFIX}.QM2.LOCAL",
                             'remote_queue_manager_name' => 'QM2',
                             'transmission_queue_name' => "#{PREFIX}.QM1.TO.QM2.XMITQ",
                             'description' => 'remote queue QM1 to QM2' })
            tracker.define(qm2, :define_qremote, "#{PREFIX}.REMOTE.TO.QM1",
                           { 'replace' => 'yes', 'remote_queue_name' => "#{PREFIX}.QM1.LOCAL",
                             'remote_queue_manager_name' => 'QM1',
                             'transmission_queue_name' => "#{PREFIX}.QM2.TO.QM1.XMITQ",
                             'description' => 'remote queue QM2 to QM1' })
          end

          def self.provision_channels(tracker, qm1, qm2)
            tracker.define(qm1, :define_channel, "#{PREFIX}.QM1.TO.QM2",
                           { 'replace' => 'yes', 'channel_type' => 'SDR', 'transport_type' => 'TCP',
                             'connection_name' => 'qm2(1414)',
                             'transmission_queue_name' => "#{PREFIX}.QM1.TO.QM2.XMITQ",
                             'description' => 'sender QM1 to QM2' })
            tracker.define(qm2, :define_channel, "#{PREFIX}.QM1.TO.QM2",
                           { 'replace' => 'yes', 'channel_type' => 'RCVR', 'transport_type' => 'TCP',
                             'description' => 'receiver QM1 to QM2' })
            tracker.define(qm2, :define_channel, "#{PREFIX}.QM2.TO.QM1",
                           { 'replace' => 'yes', 'channel_type' => 'SDR', 'transport_type' => 'TCP',
                             'connection_name' => 'qm1(1414)',
                             'transmission_queue_name' => "#{PREFIX}.QM2.TO.QM1.XMITQ",
                             'description' => 'sender QM2 to QM1' })
            tracker.define(qm1, :define_channel, "#{PREFIX}.QM2.TO.QM1",
                           { 'replace' => 'yes', 'channel_type' => 'RCVR', 'transport_type' => 'TCP',
                             'description' => 'receiver QM2 to QM1' })
          end

          def self.verify_objects(qm1, qm2)
            qm1_queues = qm1.display_queue(name: "#{PREFIX}.*")
            qm2_queues = qm2.display_queue(name: "#{PREFIX}.*")
            qm1_queues.length >= 3 && qm2_queues.length >= 3
          rescue MQ::REST::Admin::Error
            false
          end

          def self.delete_object(failures, session, method_name, name, label)
            session.send(method_name, name)
          rescue MQ::REST::Admin::Error
            failures << "#{label}/#{name}"
          end

          private_class_method :provision_local_queues, :provision_xmit_queues,
                               :provision_remote_queues, :provision_channels,
                               :verify_objects, :delete_object
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  qm1_session = MQ::REST::Admin::Session.new(
    ENV.fetch('MQ_REST_BASE_URL', 'https://localhost:9473/ibmmq/rest/v2'),
    'QM1',
    credentials: MQ::REST::Admin::BasicAuth.new(
      username: ENV.fetch('MQ_ADMIN_USER', 'mqadmin'),
      password: ENV.fetch('MQ_ADMIN_PASSWORD', 'mqadmin')
    ),
    tls_ca_file: ENV.fetch('MQ_REST_TLS_CA_FILE', nil)
  )

  qm2_session = MQ::REST::Admin::Session.new(
    ENV.fetch('MQ_REST_BASE_URL_QM2', 'https://localhost:9474/ibmmq/rest/v2'),
    'QM2',
    credentials: MQ::REST::Admin::BasicAuth.new(
      username: ENV.fetch('MQ_ADMIN_USER', 'mqadmin'),
      password: ENV.fetch('MQ_ADMIN_PASSWORD', 'mqadmin')
    ),
    tls_ca_file: ENV.fetch('MQ_REST_TLS_CA_FILE', nil)
  )

  MQ::REST::Admin::Examples::ProvisionEnvironment.main(qm1_session, qm2_session)
end
