# frozen_string_literal: true

return unless ENV['MQ_REST_ADMIN_RUN_INTEGRATION'] == '1'

require 'minitest/autorun'
require 'mq/rest/admin'
require_relative 'dev_tls_trust'

require_relative '../../examples/health_check'
require_relative '../../examples/queue_depth_monitor'
require_relative '../../examples/channel_status'
require_relative '../../examples/provision_environment'
require_relative '../../examples/dlq_inspector'
require_relative '../../examples/queue_status'

class ExamplesIntegrationTest < Minitest::Test
  QM1_URL = ENV.fetch('MQ_REST_BASE_URL', 'https://localhost:9473/ibmmq/rest/v2')
  QM2_URL = ENV.fetch('MQ_REST_BASE_URL_QM2', 'https://localhost:9474/ibmmq/rest/v2')

  def dev_ca_file
    @dev_ca_file ||= DevTLSTrust.ca_file_for([QM1_URL, QM2_URL])
  end

  def qm1_session
    MQ::REST::Admin::Session.new(
      QM1_URL,
      'QM1',
      credentials: MQ::REST::Admin::BasicAuth.new(
        username: ENV.fetch('MQ_ADMIN_USER', 'mqadmin'),
        password: ENV.fetch('MQ_ADMIN_PASSWORD', 'mqadmin')
      ),
      tls_ca_file: dev_ca_file
    )
  end

  def qm2_session
    MQ::REST::Admin::Session.new(
      QM2_URL,
      'QM2',
      credentials: MQ::REST::Admin::BasicAuth.new(
        username: ENV.fetch('MQ_ADMIN_USER', 'mqadmin'),
        password: ENV.fetch('MQ_ADMIN_PASSWORD', 'mqadmin')
      ),
      tls_ca_file: dev_ca_file
    )
  end

  # ---------------------------------------------------------------------------
  # Health check
  # ---------------------------------------------------------------------------

  def test_health_check_qm1
    result = MQ::REST::Admin::Examples::HealthCheck.check_health(qm1_session)

    assert result.reachable, 'QM1 should be reachable'
    assert result.passed, 'QM1 health check should pass'
    assert_equal 'QM1', result.qmgr_name
  end

  def test_health_check_qm2
    result = MQ::REST::Admin::Examples::HealthCheck.check_health(qm2_session)

    assert result.reachable, 'QM2 should be reachable'
    assert result.passed, 'QM2 health check should pass'
    assert_equal 'QM2', result.qmgr_name
  end

  # ---------------------------------------------------------------------------
  # Queue depth monitor
  # ---------------------------------------------------------------------------

  def test_queue_depth_monitor
    results = MQ::REST::Admin::Examples::QueueDepthMonitor.monitor_queue_depths(qm1_session)

    refute_empty results, 'Should find local queues'
    assert results.any? { |q| q.name == 'DEV.QLOCAL' },
           'Should include DEV.QLOCAL'
  end

  # ---------------------------------------------------------------------------
  # Channel status
  # ---------------------------------------------------------------------------

  def test_channel_status_report
    results = MQ::REST::Admin::Examples::ChannelStatus.report_channel_status(qm1_session)

    refute_empty results, 'Should find channels'
    assert results.any? { |c| c.name == 'DEV.SVRCONN' },
           'Should include DEV.SVRCONN'
  end

  # ---------------------------------------------------------------------------
  # DLQ inspector
  # ---------------------------------------------------------------------------

  def test_dlq_inspector
    report = MQ::REST::Admin::Examples::DLQInspector.inspect_dlq(qm1_session)

    assert report.configured, 'DLQ should be configured'
    assert_equal 'DEV.DEAD.LETTER', report.dlq_name
    assert_equal 0, report.current_depth
  end

  # ---------------------------------------------------------------------------
  # Queue status
  # ---------------------------------------------------------------------------

  def test_queue_status_handles
    queue_handles = MQ::REST::Admin::Examples::QueueStatus.report_queue_handles(qm1_session)

    assert_kind_of Array, queue_handles
  end

  def test_connection_handles
    conn_handles = MQ::REST::Admin::Examples::QueueStatus.report_connection_handles(qm1_session)

    assert_kind_of Array, conn_handles
  end

  # ---------------------------------------------------------------------------
  # Provision and teardown
  # ---------------------------------------------------------------------------

  def test_provision_and_teardown
    qm1 = qm1_session
    qm2 = qm2_session

    result = MQ::REST::Admin::Examples::ProvisionEnvironment.provision(qm1, qm2)

    refute_empty result.objects_created, 'Should create objects'
    assert result.verified, 'Verification should pass'

    failures = MQ::REST::Admin::Examples::ProvisionEnvironment.teardown(qm1, qm2)

    assert_empty failures, "Teardown failures: #{failures}"
  end
end
