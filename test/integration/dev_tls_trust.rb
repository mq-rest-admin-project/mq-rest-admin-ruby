# frozen_string_literal: true

require 'open3'
require 'tempfile'
require 'uri'

# Shared TLS-trust helper for the integration suite.
#
# TLS certificate verification is always enabled. The development queue
# managers use self-signed certificates, so the integration suite trusts them
# explicitly by extracting their certificate chains at runtime into a temporary
# CA bundle -- never by disabling verification. Set MQ_REST_TLS_CA_FILE to
# override with a pre-provisioned CA bundle (e.g. a corporate CA).
module DevTLSTrust
  module_function

  # Resolve a CA bundle path that trusts the given REST endpoints.
  #
  # @param rest_base_urls [Array<String>] the MQ REST base URLs to trust
  # @return [String] path to a PEM CA bundle
  def ca_file_for(rest_base_urls)
    override = ENV.fetch('MQ_REST_TLS_CA_FILE', nil)
    return override if override && !override.empty?

    blocks = extract_server_cert_chain(rest_base_urls)
    if blocks.empty?
      raise 'Could not extract dev MQ server certificates for TLS trust; ' \
            'set MQ_REST_TLS_CA_FILE to a CA bundle.'
    end

    file = Tempfile.create(['mq-dev-ca', '.pem'])
    file.write("#{blocks.join("\n")}\n")
    file.close
    file.path
  end

  # Fetch each queue manager's TLS certificate chain via the openssl CLI. This
  # only reads the certificate the server presents (it does not establish a
  # trusted, application-level connection), so it stays free of any
  # verification-disabling code in the library or test suite.
  #
  # @param rest_base_urls [Array<String>] the MQ REST base URLs
  # @return [Array<String>] unique PEM certificate blocks
  def extract_server_cert_chain(rest_base_urls)
    rest_base_urls.uniq.flat_map do |base_url|
      uri = URI.parse(base_url)
      stdout, = Open3.capture3(
        'openssl', 's_client', '-connect', "#{uri.host}:#{uri.port}",
        '-servername', uri.host.to_s, '-showcerts',
        stdin_data: ''
      )
      stdout.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m)
    end.uniq
  end
end
