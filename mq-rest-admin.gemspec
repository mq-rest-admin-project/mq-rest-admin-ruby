# frozen_string_literal: true

require_relative 'lib/mq/rest/admin/version'

Gem::Specification.new do |spec|
  spec.name = 'mq-rest-admin'
  spec.version = MQ::REST::Admin::VERSION
  spec.authors = ['W. Phillip Moore']
  spec.email = ['wphillipmoore@gmail.com']

  spec.summary = 'Ruby wrapper for the IBM MQ administrative REST API'
  spec.description = 'Typed Ruby methods for every MQSC command exposed by the ' \
                     'IBM MQ 9.4 runCommandJSON REST endpoint, with automatic ' \
                     'attribute name translation between Ruby idioms and native ' \
                     'MQSC parameter names.'
  spec.homepage = 'https://github.com/mq-rest-admin-project/mq-rest-admin-ruby'
  spec.license = 'GPL-3.0-or-later'
  spec.required_ruby_version = '>= 3.3.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    Dir['{lib}/**/*', 'LICENSE', 'README.md', 'CHANGELOG.md']
  end
  spec.require_paths = ['lib']

  # base64 was removed from Ruby's default gems in 3.4
  spec.add_dependency 'base64'
end
