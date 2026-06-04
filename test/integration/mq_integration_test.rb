# frozen_string_literal: true

return unless ENV['MQ_REST_ADMIN_RUN_INTEGRATION'] == '1'

require 'minitest/autorun'
require 'mq/rest/admin'
require_relative 'dev_tls_trust'

# ---------------------------------------------------------------------------
# Seeded object names (created by mq_seed.sh)
# ---------------------------------------------------------------------------

SEEDED_QUEUES = %w[
  DEV.DEAD.LETTER
  DEV.QLOCAL
  DEV.QREMOTE
  DEV.QALIAS
  DEV.QMODEL
  DEV.XMITQ
].freeze

SEEDED_CHANNELS = %w[
  DEV.SVRCONN
  DEV.SDR
  DEV.RCVR
].freeze

SEEDED_LISTENER = 'DEV.LSTR'
SEEDED_TOPIC    = 'DEV.TOPIC'
SEEDED_NAMELIST = 'DEV.NAMELIST'
SEEDED_PROCESS  = 'DEV.PROC'

TEST_QLOCAL   = 'DEV.TEST.QLOCAL'
TEST_QREMOTE  = 'DEV.TEST.QREMOTE'
TEST_QALIAS   = 'DEV.TEST.QALIAS'
TEST_QMODEL   = 'DEV.TEST.QMODEL'
TEST_CHANNEL  = 'DEV.TEST.SVRCONN'
TEST_LISTENER = 'DEV.TEST.LSTR'
TEST_PROCESS  = 'DEV.TEST.PROC'
TEST_TOPIC    = 'DEV.TEST.TOPIC'
TEST_NAMELIST = 'DEV.TEST.NAMELIST'

TEST_ENSURE_QLOCAL  = 'DEV.ENSURE.QLOCAL'
TEST_ENSURE_CHANNEL = 'DEV.ENSURE.CHL'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

IntegrationConfig = Data.define(
  :rest_base_url, :rest_base_url_qm2,
  :admin_user, :admin_password,
  :qmgr_name, :qmgr_name_qm2, :tls_ca_file
)

def load_integration_config
  rest_base_url = ENV.fetch('MQ_REST_BASE_URL', 'https://localhost:9473/ibmmq/rest/v2')
  rest_base_url_qm2 = ENV.fetch('MQ_REST_BASE_URL_QM2', 'https://localhost:9474/ibmmq/rest/v2')
  IntegrationConfig.new(
    rest_base_url: rest_base_url,
    rest_base_url_qm2: rest_base_url_qm2,
    admin_user: ENV.fetch('MQ_ADMIN_USER', 'mqadmin'),
    admin_password: ENV.fetch('MQ_ADMIN_PASSWORD', 'mqadmin'),
    qmgr_name: ENV.fetch('MQ_QMGR_NAME', 'QM1'),
    qmgr_name_qm2: ENV.fetch('MQ_QMGR_NAME_QM2', 'QM2'),
    tls_ca_file: DevTLSTrust.ca_file_for([rest_base_url, rest_base_url_qm2])
  )
end

# ---------------------------------------------------------------------------
# Session builders
# ---------------------------------------------------------------------------

def build_session(config, map_attributes: true, mapping_strict: true)
  MQ::REST::Admin::Session.new(
    config.rest_base_url, config.qmgr_name,
    credentials: MQ::REST::Admin::BasicAuth.new(username: config.admin_user, password: config.admin_password),
    tls_ca_file: config.tls_ca_file,
    map_attributes: map_attributes,
    mapping_strict: mapping_strict
  )
end

def build_gateway_session(config, target_qmgr:, gateway_qmgr:, rest_base_url:)
  MQ::REST::Admin::Session.new(
    rest_base_url, target_qmgr,
    credentials: MQ::REST::Admin::BasicAuth.new(username: config.admin_user, password: config.admin_password),
    gateway_qmgr: gateway_qmgr,
    tls_ca_file: config.tls_ca_file
  )
end

# Probe whether the MQ REST endpoint is up over verified TLS, dogfooding the
# library's own secure path. Returns false on any failure so it can drive a
# readiness poll without ever disabling certificate verification.
def rest_ready?(base_url, qmgr, admin_user, admin_password)
  session = MQ::REST::Admin::Session.new(
    base_url, qmgr,
    credentials: MQ::REST::Admin::BasicAuth.new(username: admin_user, password: admin_password),
    tls_ca_file: DevTLSTrust.ca_file_for([base_url]),
    timeout_seconds: 5
  )
  session.display_qmgr
  true
rescue StandardError
  false
end

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

def contains_string_value?(obj, expected)
  normalized = expected.to_s.strip.upcase
  obj.each_value do |v|
    return true if v.is_a?(String) && v.strip.upcase == normalized
  end
  false
end

def any_contains_value(results, expected)
  results.any? { |obj| contains_string_value?(obj, expected) }
end

def find_matching_object(result, expected)
  case result
  when Hash
    contains_string_value?(result, expected) ? result : nil
  when Array
    result.find { |obj| obj.is_a?(Hash) && contains_string_value?(obj, expected) }
  end
end

def get_attribute_case_insensitive(obj, name)
  upper = name.upcase
  obj.each do |k, v|
    return v if k.to_s.upcase == upper
  end
  nil
end

# Methods that take name as a positional (non-keyword) argument.
POSITIONAL_NAME_METHODS = %i[
  define_qlocal define_qremote define_qalias define_qmodel define_channel
  delete_qlocal delete_qremote delete_qalias delete_qmodel
  delete_queue delete_channel
  display_listener display_namelist display_process display_topic display_qstatus
  ensure_qlocal ensure_qremote ensure_qalias ensure_qmodel ensure_channel
  ensure_listener ensure_namelist ensure_process ensure_topic
].freeze

def invoke_method(session, method_name, name, request_parameters: nil)
  sym = method_name.to_sym
  if POSITIONAL_NAME_METHODS.include?(sym)
    if request_parameters
      session.send(sym, name, request_parameters: request_parameters)
    else
      session.send(sym, name)
    end
  elsif request_parameters
    session.send(sym, name: name, request_parameters: request_parameters)
  else
    session.send(sym, name: name)
  end
end

# ---------------------------------------------------------------------------
# Lifecycle case definition
# ---------------------------------------------------------------------------

LifecycleCase = Data.define(
  :name, :object_name,
  :define_method, :display_method, :delete_method,
  :define_parameters,
  :alter_method, :alter_parameters, :alter_description
) do
  def initialize(alter_method: nil, alter_parameters: nil, alter_description: nil, **rest)
    super
  end
end

class MqIntegrationTest < Minitest::Test
  REPO_ROOT = File.expand_path('../..', __dir__)
  MQ_START_SCRIPT = File.join(REPO_ROOT, 'scripts/dev/mq_start.sh')
  MQ_SEED_SCRIPT  = File.join(REPO_ROOT, 'scripts/dev/mq_seed.sh')
  MQ_STOP_SCRIPT  = File.join(REPO_ROOT, 'scripts/dev/mq_stop.sh')
  MQ_READY_TIMEOUT = 90
  MQ_READY_SLEEP   = 2

  @@lifecycle_started = false # rubocop:disable Style/ClassVars

  def setup
    unless @@lifecycle_started
      @@lifecycle_started = true # rubocop:disable Style/ClassVars
      skip_lifecycle = %w[1 true yes].include?(ENV.fetch('MQ_SKIP_LIFECYCLE', '').strip.downcase)
      unless skip_lifecycle
        run_lifecycle_script(MQ_START_SCRIPT)
        wait_for_rest_ready
        run_lifecycle_script(MQ_SEED_SCRIPT)
      end
      Minitest.after_run do
        run_lifecycle_script(MQ_STOP_SCRIPT) unless skip_lifecycle
      end
    end
    @config = load_integration_config
    @session = build_session(@config)
  end

  # -------------------------------------------------------------------------
  # Display tests - singletons
  # -------------------------------------------------------------------------

  def test_display_qmgr_returns_object
    result = @session.display_qmgr

    refute_nil result
    assert_kind_of Hash, result
    assert contains_string_value?(result, @config.qmgr_name),
           "display_qmgr result does not contain #{@config.qmgr_name}"
  end

  def test_display_qmstatus_returns_object_or_nil
    result = @session.display_qmstatus

    assert(result.nil? || result.is_a?(Hash), 'Expected nil or Hash')
  end

  def test_display_cmdserv_returns_object_or_nil
    result = @session.display_cmdserv

    assert(result.nil? || result.is_a?(Hash), 'Expected nil or Hash')
  end

  # -------------------------------------------------------------------------
  # Display tests - seeded queues
  # -------------------------------------------------------------------------

  SEEDED_QUEUES.each do |queue_name|
    define_method(:"test_display_seeded_queue_#{queue_name.downcase.tr('.', '_')}") do
      results = @session.display_queue(name: queue_name)

      refute_empty results, "display_queue(#{queue_name}) returned empty"
      assert any_contains_value(results, queue_name),
             "display_queue results do not contain #{queue_name}"
    end
  end

  # -------------------------------------------------------------------------
  # Display tests - qstatus
  # -------------------------------------------------------------------------

  def test_display_qstatus_returns_results
    results = @session.display_qstatus('DEV.QLOCAL')

    refute_empty results, 'display_qstatus returned empty'
    assert any_contains_value(results, 'DEV.QLOCAL'),
           'display_qstatus results do not contain DEV.QLOCAL'
  end

  # -------------------------------------------------------------------------
  # Display tests - seeded channels
  # -------------------------------------------------------------------------

  SEEDED_CHANNELS.each do |channel_name|
    define_method(:"test_display_seeded_channel_#{channel_name.downcase.tr('.', '_')}") do
      results = @session.display_channel(name: channel_name)

      refute_empty results, "display_channel(#{channel_name}) returned empty"
      assert any_contains_value(results, channel_name),
             "display_channel results do not contain #{channel_name}"
    end
  end

  # -------------------------------------------------------------------------
  # Display tests - seeded objects
  # -------------------------------------------------------------------------

  def test_display_seeded_listener
    results = @session.display_listener(SEEDED_LISTENER)

    refute_empty results
    assert any_contains_value(results, SEEDED_LISTENER)
  end

  def test_display_seeded_topic
    results = @session.display_topic(SEEDED_TOPIC)

    refute_empty results
    assert any_contains_value(results, SEEDED_TOPIC)
  end

  def test_display_seeded_namelist
    results = @session.display_namelist(SEEDED_NAMELIST)

    refute_empty results
    assert any_contains_value(results, SEEDED_NAMELIST)
  end

  def test_display_seeded_process
    results = @session.display_process(SEEDED_PROCESS)

    refute_empty results
    assert any_contains_value(results, SEEDED_PROCESS)
  end

  # -------------------------------------------------------------------------
  # Lifecycle CRUD tests
  # -------------------------------------------------------------------------

  def test_mutating_object_lifecycle
    lifecycle_cases.each do |lcase|
      run_lifecycle_case(lcase)
    end
  end

  # -------------------------------------------------------------------------
  # Ensure idempotent tests
  # -------------------------------------------------------------------------

  def test_ensure_qmgr_lifecycle
    # Read current description so we can restore it.
    qmgr = @session.display_qmgr

    refute_nil qmgr
    original_descr = qmgr.fetch('description', '')

    test_descr = 'dev ensure_qmgr test'

    # Alter to test value.
    result = @session.ensure_qmgr(request_parameters: { 'description' => test_descr })

    assert_includes %i[updated unchanged], result.action

    # Unchanged (same attributes).
    result = @session.ensure_qmgr(request_parameters: { 'description' => test_descr })

    assert_equal :unchanged, result.action

    # Restore original description.
    @session.ensure_qmgr(request_parameters: { 'description' => original_descr })
  end

  def test_ensure_qlocal_lifecycle
    session = build_session(@config, mapping_strict: false)

    # Clean up from any prior failed run.
    begin
      session.delete_qlocal(TEST_ENSURE_QLOCAL)
    rescue MQ::REST::Admin::Error # rubocop:disable Lint/SuppressedException
    end

    # Create.
    result = session.ensure_qlocal(TEST_ENSURE_QLOCAL, request_parameters: { 'description' => 'ensure test' })

    assert_equal :created, result.action

    # Unchanged (same attributes).
    result = session.ensure_qlocal(TEST_ENSURE_QLOCAL, request_parameters: { 'description' => 'ensure test' })

    assert_equal :unchanged, result.action

    # Updated (different attribute).
    result = session.ensure_qlocal(TEST_ENSURE_QLOCAL, request_parameters: { 'description' => 'ensure updated' })

    assert_equal :updated, result.action

    # Cleanup.
    session.delete_qlocal(TEST_ENSURE_QLOCAL)
  end

  def test_ensure_channel_lifecycle
    session = build_session(@config, mapping_strict: false)

    # Clean up from any prior failed run.
    begin
      session.delete_channel(TEST_ENSURE_CHANNEL)
    rescue MQ::REST::Admin::Error # rubocop:disable Lint/SuppressedException
    end

    # Create.
    result = session.ensure_channel(
      TEST_ENSURE_CHANNEL,
      request_parameters: { 'channel_type' => 'SVRCONN', 'description' => 'ensure test' }
    )

    assert_equal :created, result.action

    # Unchanged.
    result = session.ensure_channel(
      TEST_ENSURE_CHANNEL,
      request_parameters: { 'channel_type' => 'SVRCONN', 'description' => 'ensure test' }
    )

    assert_equal :unchanged, result.action

    # Updated.
    result = session.ensure_channel(
      TEST_ENSURE_CHANNEL,
      request_parameters: { 'channel_type' => 'SVRCONN', 'description' => 'ensure updated' }
    )

    assert_equal :updated, result.action

    # Cleanup.
    session.delete_channel(TEST_ENSURE_CHANNEL)
  end

  # -------------------------------------------------------------------------
  # Gateway multi-QM tests
  # -------------------------------------------------------------------------

  def test_gateway_display_qmgr_qm2_via_qm1
    session = build_gateway_session(
      @config,
      target_qmgr: @config.qmgr_name_qm2,
      gateway_qmgr: @config.qmgr_name,
      rest_base_url: @config.rest_base_url
    )

    result = session.display_qmgr

    refute_nil result
    assert_kind_of Hash, result
    assert contains_string_value?(result, @config.qmgr_name_qm2),
           "gateway display_qmgr does not contain #{@config.qmgr_name_qm2}"
  end

  def test_gateway_display_qmgr_qm1_via_qm2
    session = build_gateway_session(
      @config,
      target_qmgr: @config.qmgr_name,
      gateway_qmgr: @config.qmgr_name_qm2,
      rest_base_url: @config.rest_base_url_qm2
    )

    result = session.display_qmgr

    refute_nil result
    assert_kind_of Hash, result
    assert contains_string_value?(result, @config.qmgr_name),
           "gateway display_qmgr does not contain #{@config.qmgr_name}"
  end

  def test_gateway_display_queue_qm2_via_qm1
    session = build_gateway_session(
      @config,
      target_qmgr: @config.qmgr_name_qm2,
      gateway_qmgr: @config.qmgr_name,
      rest_base_url: @config.rest_base_url
    )

    results = session.display_queue(name: 'DEV.QLOCAL')

    refute_empty results
    assert any_contains_value(results, 'DEV.QLOCAL')
  end

  def test_gateway_session_properties
    session = build_gateway_session(
      @config,
      target_qmgr: @config.qmgr_name_qm2,
      gateway_qmgr: @config.qmgr_name,
      rest_base_url: @config.rest_base_url
    )

    assert_equal @config.qmgr_name_qm2, session.qmgr_name
    assert_equal @config.qmgr_name, session.gateway_qmgr
  end

  # -------------------------------------------------------------------------
  # Session state test
  # -------------------------------------------------------------------------

  def test_session_state_populated_after_command
    @session.display_qmgr

    refute_nil @session.last_http_status, 'last_http_status should not be nil'
    assert_predicate @session.last_http_status, :positive?, 'last_http_status should be positive'
    refute_nil @session.last_response_text, 'last_response_text should not be nil'
    refute_empty @session.last_response_text, 'last_response_text should not be empty'
  end

  # -------------------------------------------------------------------------
  # LTPA auth test
  # -------------------------------------------------------------------------

  def test_ltpa_auth_display_qmgr
    session = MQ::REST::Admin::Session.new(
      @config.rest_base_url, @config.qmgr_name,
      credentials: MQ::REST::Admin::LTPAAuth.new(username: @config.admin_user, password: @config.admin_password),
      tls_ca_file: @config.tls_ca_file
    )

    result = session.display_qmgr

    refute_nil result
    assert_kind_of Hash, result
    assert contains_string_value?(result, @config.qmgr_name)
  end

  private

  # -------------------------------------------------------------------------
  # Lifecycle helpers
  # -------------------------------------------------------------------------

  def lifecycle_cases
    [
      LifecycleCase.new(
        name: 'qlocal', object_name: TEST_QLOCAL,
        define_method: :define_qlocal, display_method: :display_queue, delete_method: :delete_qlocal,
        define_parameters: { 'replace' => 'yes', 'default_persistence' => 'yes', 'description' => 'dev test qlocal' }
      ),
      LifecycleCase.new(
        name: 'qremote', object_name: TEST_QREMOTE,
        define_method: :define_qremote, display_method: :display_queue, delete_method: :delete_qremote,
        define_parameters: {
          'replace' => 'yes', 'remote_queue_name' => 'DEV.TARGET',
          'remote_queue_manager_name' => @config.qmgr_name,
          'transmission_queue_name' => 'DEV.XMITQ', 'description' => 'dev test qremote'
        }
      ),
      LifecycleCase.new(
        name: 'qalias', object_name: TEST_QALIAS,
        define_method: :define_qalias, display_method: :display_queue, delete_method: :delete_qalias,
        define_parameters: {
          'replace' => 'yes', 'target_queue_name' => 'DEV.QLOCAL', 'description' => 'dev test qalias'
        }
      ),
      LifecycleCase.new(
        name: 'qmodel', object_name: TEST_QMODEL,
        define_method: :define_qmodel, display_method: :display_queue, delete_method: :delete_qmodel,
        define_parameters: {
          'replace' => 'yes', 'definition_type' => 'TEMPDYN',
          'default_input_open_option' => 'SHARED', 'description' => 'dev test qmodel'
        }
      ),
      LifecycleCase.new(
        name: 'channel', object_name: TEST_CHANNEL,
        define_method: :define_channel, display_method: :display_channel, delete_method: :delete_channel,
        define_parameters: {
          'replace' => 'yes', 'channel_type' => 'SVRCONN',
          'transport_type' => 'TCP', 'description' => 'dev test channel'
        },
        alter_method: :alter_channel,
        alter_parameters: { 'channel_type' => 'SVRCONN', 'description' => 'dev test channel updated' },
        alter_description: 'dev test channel updated'
      ),
      LifecycleCase.new(
        name: 'listener', object_name: TEST_LISTENER,
        define_method: :define_listener, display_method: :display_listener, delete_method: :delete_listener,
        define_parameters: {
          'replace' => 'yes', 'transport_type' => 'TCP', 'port' => 1416,
          'start_mode' => 'QMGR', 'description' => 'dev test listener'
        },
        alter_method: :alter_listener,
        alter_parameters: { 'transport_type' => 'TCP', 'description' => 'dev test listener updated' },
        alter_description: 'dev test listener updated'
      ),
      LifecycleCase.new(
        name: 'process', object_name: TEST_PROCESS,
        define_method: :define_process, display_method: :display_process, delete_method: :delete_process,
        define_parameters: {
          'replace' => 'yes', 'application_id' => '/bin/true', 'description' => 'dev test process'
        },
        alter_method: :alter_process,
        alter_parameters: { 'description' => 'dev test process updated' },
        alter_description: 'dev test process updated'
      ),
      LifecycleCase.new(
        name: 'topic', object_name: TEST_TOPIC,
        define_method: :define_topic, display_method: :display_topic, delete_method: :delete_topic,
        define_parameters: {
          'replace' => 'yes', 'topic_string' => 'dev/test', 'description' => 'dev test topic'
        },
        alter_method: :alter_topic,
        alter_parameters: { 'description' => 'dev test topic updated' },
        alter_description: 'dev test topic updated'
      ),
      LifecycleCase.new(
        name: 'namelist', object_name: TEST_NAMELIST,
        define_method: :define_namelist, display_method: :display_namelist, delete_method: :delete_namelist,
        define_parameters: {
          'replace' => 'yes', 'names' => ['DEV.QLOCAL'], 'description' => 'dev test namelist'
        },
        alter_method: :alter_namelist,
        alter_parameters: { 'description' => 'dev test namelist updated' },
        alter_description: 'dev test namelist updated'
      )
    ]
  end

  def run_lifecycle_case(lcase)
    # Define.
    invoke_method(@session, lcase.define_method, lcase.object_name, request_parameters: lcase.define_parameters)

    # Display and verify.
    display_result = invoke_method(@session, lcase.display_method, lcase.object_name)

    assert find_matching_object(display_result, lcase.object_name),
           "#{lcase.name}: display after define did not contain #{lcase.object_name}"

    # Alter (if applicable).
    if lcase.alter_method
      invoke_method(@session, lcase.alter_method, lcase.object_name, request_parameters: lcase.alter_parameters)
      updated = invoke_method(@session, lcase.display_method, lcase.object_name)
      if lcase.alter_description
        matched = find_matching_object(updated, lcase.object_name)

        assert matched, "#{lcase.name}: display after alter did not contain #{lcase.object_name}"
        desc = get_attribute_case_insensitive(matched, 'description') ||
               get_attribute_case_insensitive(matched, 'DESCR')

        assert_equal lcase.alter_description, desc, "#{lcase.name}: alter description mismatch"
      end
    end

    # Delete.
    invoke_method(@session, lcase.delete_method, lcase.object_name)

    # Verify deletion.
    begin
      deleted = invoke_method(@session, lcase.display_method, lcase.object_name)
    rescue MQ::REST::Admin::Error
      return # Error on display after delete is acceptable.
    end

    refute find_matching_object(deleted, lcase.object_name),
           "#{lcase.name}: object still visible after delete"
  end

  def run_lifecycle_script(script_path)
    system('bash', script_path, exception: true)
  end

  def wait_for_rest_ready
    base_url = ENV.fetch('MQ_REST_BASE_URL', 'https://localhost:9473/ibmmq/rest/v2')
    qmgr = ENV.fetch('MQ_QMGR_NAME', 'QM1')
    user = ENV.fetch('MQ_ADMIN_USER', 'mqadmin')
    pass = ENV.fetch('MQ_ADMIN_PASSWORD', 'mqadmin')
    deadline = Time.now + MQ_READY_TIMEOUT

    while Time.now < deadline
      # Cert extraction + a verified request only succeed once MQ is up, so this
      # is both the readiness gate and proof that verified TLS works.
      return if rest_ready?(base_url, qmgr, user, pass)

      sleep MQ_READY_SLEEP
    end
    raise "MQ REST endpoint not ready after #{MQ_READY_TIMEOUT}s"
  end
end
