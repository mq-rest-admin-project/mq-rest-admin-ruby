# frozen_string_literal: true

module MQ
  module REST
    module Admin
      # @return [Array<String>] default response parameter list requesting all attributes
      DEFAULT_RESPONSE_PARAMETERS = ['all'].freeze

      # @return [String] default CSRF token value for local connections
      DEFAULT_CSRF_TOKEN = 'local'

      # @return [String] HTTP header name for gateway queue manager routing
      GATEWAY_HEADER = 'ibm-mq-rest-gateway-qmgr'

      # @return [Hash{String => String}] mapping from MQSC qualifiers to mapping qualifier names
      DEFAULT_MAPPING_QUALIFIERS = {
        'QUEUE' => 'queue',
        'QLOCAL' => 'queue',
        'QREMOTE' => 'queue',
        'QALIAS' => 'queue',
        'QMODEL' => 'queue',
        'QMSTATUS' => 'qmstatus',
        'QSTATUS' => 'qstatus',
        'CHANNEL' => 'channel',
        'QMGR' => 'qmgr'
      }.freeze

      # Primary entry point for interacting with IBM MQ via the REST API.
      #
      # A session wraps a connection to a single queue manager and provides
      # MQSC command execution, idempotent object configuration, and
      # synchronous start/stop/restart operations.
      #
      # @example Basic usage with HTTP Basic authentication
      #   session = Session.new(
      #     "https://mq.example.com:9443/ibmmq/rest/v2",
      #     "QM1",
      #     credentials: BasicAuth.new(username: "admin", password: "secret")
      #   )
      #   queues = session.display_queue
      #
      # @example Idempotent queue configuration
      #   result = session.ensure_qlocal("MY.QUEUE", request_parameters: { "max_depth" => "5000" })
      #   puts result.action  # => :created, :updated, or :unchanged
      class Session
        include Commands
        include Ensure
        include Sync
        include SessionHelpers

        # @return [String] the queue manager name
        attr_reader :qmgr_name

        # @return [String, nil] the gateway queue manager name, if routing through a gateway
        attr_reader :gateway_qmgr

        # @return [Hash{String => Object}, nil] the last parsed MQ REST response payload
        attr_accessor :last_response_payload

        # @return [String, nil] the last raw response body text
        attr_accessor :last_response_text

        # @return [Integer, nil] the last HTTP status code
        attr_accessor :last_http_status

        # @return [Hash{String => Object}, nil] the last command payload sent
        attr_accessor :last_command_payload

        # Create a new MQ REST Admin session.
        #
        # @param rest_base_url [String] the MQ REST API base URL
        # @param qmgr_name [String] the queue manager name
        # @param credentials [BasicAuth, LTPAAuth, CertificateAuth] authentication credentials
        # @param gateway_qmgr [String, nil] optional gateway queue manager name
        # @param tls_ca_file [String, nil] path to a PEM CA bundle to trust for
        #   TLS verification (for internal or self-signed CAs); nil uses the
        #   system trust store. TLS certificates are always verified.
        # @param timeout_seconds [Float] request timeout in seconds
        # @param map_attributes [Boolean] whether to auto-map snake_case to MQSC attributes
        # @param mapping_strict [Boolean] whether to raise on unknown mapping attributes
        # @param mapping_overrides [Hash{String => Object}, nil] custom mapping data overrides
        # @param mapping_overrides_mode [Symbol] +:merge+ or +:replace+
        # @param csrf_token [String, nil] CSRF token for authenticated requests
        # @param transport [NetHTTPTransport, nil] custom transport (defaults to {NetHTTPTransport})
        # @raise [AuthError] if LTPA login fails when using {LTPAAuth} credentials
        def initialize(
          rest_base_url,
          qmgr_name,
          credentials:,
          gateway_qmgr: nil,
          tls_ca_file: nil,
          timeout_seconds: 30.0,
          map_attributes: true,
          mapping_strict: true,
          mapping_overrides: nil,
          mapping_overrides_mode: MAPPING_OVERRIDE_MERGE,
          csrf_token: DEFAULT_CSRF_TOKEN,
          transport: nil
        )
          @rest_base_url = rest_base_url.chomp('/')
          @qmgr_name = qmgr_name
          @gateway_qmgr = gateway_qmgr
          @tls_ca_file = tls_ca_file
          @timeout_seconds = timeout_seconds
          @map_attributes = map_attributes
          @mapping_strict = mapping_strict
          @csrf_token = csrf_token
          @credentials = credentials

          @mapping_data = resolve_mapping_data(mapping_overrides, mapping_overrides_mode)
          @transport = resolve_transport(credentials, transport)

          @ltpa_cookie_name = nil
          @ltpa_token = nil
          if credentials.is_a?(LTPAAuth)
            @ltpa_cookie_name, @ltpa_token = Admin.perform_ltpa_login(
              @transport, @rest_base_url, credentials,
              csrf_token: @csrf_token,
              timeout_seconds: @timeout_seconds
            )
          end

          @last_response_payload = nil
          @last_response_text = nil
          @last_http_status = nil
          @last_command_payload = nil
        end

        private

        def mqsc_command(command:, mqsc_qualifier:, name:, request_parameters:, response_parameters:, where: nil)
          command_upper = command.strip.upcase
          qualifier_upper = mqsc_qualifier.strip.upcase
          norm_request = request_parameters ? request_parameters.to_h : {}
          norm_response = normalize_response_parameters(response_parameters, is_display: command_upper == 'DISPLAY')
          do_map = @map_attributes
          mapping_qualifier = resolve_mapping_qualifier(command_upper, qualifier_upper)

          if do_map
            norm_request = Mapping.map_request_attributes(
              mapping_qualifier, norm_request,
              strict: @mapping_strict, mapping_data: @mapping_data
            )
            norm_response = map_response_parameters(
              command_upper, qualifier_upper, mapping_qualifier, norm_response
            )
          end

          if where && !where.strip.empty?
            mapped_where = where
            if do_map
              mapped_where = map_where_keyword(
                where, mapping_qualifier,
                strict: @mapping_strict, mapping_data: @mapping_data
              )
            end
            norm_request['WHERE'] = mapped_where
          end

          payload = build_command_payload(
            command: command_upper, qualifier: qualifier_upper,
            name: name, request_parameters: norm_request,
            response_parameters: norm_response
          )
          @last_command_payload = payload.dup

          response_payload = execute_transport_request(payload)
          extract_result_objects(response_payload, mapping_qualifier, do_map)
        end

        def build_mqsc_url
          "#{@rest_base_url}/admin/action/qmgr/#{@qmgr_name}/mqsc"
        end

        def execute_transport_request(payload)
          transport_response = @transport.post_json(
            build_mqsc_url, payload,
            headers: build_headers,
            timeout_seconds: @timeout_seconds
          )
          @last_http_status = transport_response.status_code
          @last_response_text = transport_response.body

          response_payload = parse_response_payload(transport_response.body)
          @last_response_payload = response_payload
          raise_for_command_errors(response_payload, transport_response.status_code)
          response_payload
        end

        def extract_result_objects(response_payload, mapping_qualifier, do_map)
          command_response = extract_command_response(response_payload)
          parameter_objects = command_response.map do |item|
            params = item['parameters']
            params.is_a?(Hash) ? params.dup : {}
          end

          parameter_objects = flatten_nested_objects(parameter_objects)

          if do_map
            normalized = parameter_objects.map { |item| normalize_response_attributes(item) }
            return Mapping.map_response_list(
              mapping_qualifier, normalized,
              strict: @mapping_strict, mapping_data: @mapping_data
            )
          end

          parameter_objects
        end

        def build_headers
          headers = { 'Accept' => 'application/json' }
          if @credentials.is_a?(BasicAuth)
            headers['Authorization'] = build_basic_auth_header(
              @credentials.username, @credentials.password
            )
          elsif @credentials.is_a?(LTPAAuth) && @ltpa_token
            headers['Cookie'] = "#{@ltpa_cookie_name}=#{@ltpa_token}"
          end
          headers['ibm-mq-rest-csrf-token'] = @csrf_token unless @csrf_token.nil?
          headers[GATEWAY_HEADER] = @gateway_qmgr unless @gateway_qmgr.nil? # steep:ignore
          headers
        end

        def raise_for_command_errors(payload, status_code)
          overall_completion_code = extract_optional_int(payload['overallCompletionCode'])
          overall_reason_code = extract_optional_int(payload['overallReasonCode'])
          has_overall = error_codes?(overall_completion_code, overall_reason_code)

          command_issues = []
          command_response = payload['commandResponse']
          if command_response.is_a?(Array)
            command_response.each_with_index do |item, item_index|
              next unless item.is_a?(Hash)

              completion_code = extract_optional_int(item['completionCode'])
              reason_code = extract_optional_int(item['reasonCode'])
              next unless error_codes?(completion_code, reason_code)

              command_issues << "index=#{item_index} completionCode=#{completion_code} reasonCode=#{reason_code}"
            end
          end

          return unless has_overall || !command_issues.empty?

          lines = ['MQ REST command failed.']
          if has_overall
            lines << "overallCompletionCode=#{overall_completion_code} overallReasonCode=#{overall_reason_code}"
          end
          unless command_issues.empty?
            lines << 'commandResponse:'
            lines.concat(command_issues)
          end
          raise CommandError.new(
            lines.join("\n"),
            payload: payload, status_code: status_code
          )
        end

        def resolve_mapping_qualifier(command, mqsc_qualifier)
          command_map = get_command_map(@mapping_data)
          command_key = "#{command} #{mqsc_qualifier}"
          command_definition = command_map[command_key]
          if command_definition.is_a?(Hash)
            qualifier = command_definition['qualifier']
            return qualifier if qualifier.is_a?(String)
          end
          fallback = DEFAULT_MAPPING_QUALIFIERS[mqsc_qualifier]
          return fallback unless fallback.nil?

          mqsc_qualifier.downcase
        end

        def map_response_parameters(command, mqsc_qualifier, mapping_qualifier, response_parameters)
          return response_parameters if all_response_parameters?(response_parameters)

          macros = get_response_parameter_macros(command, mqsc_qualifier, mapping_data: @mapping_data)
          macro_lookup = macros.to_h { |macro| [macro.downcase, macro] }

          qualifier_entry = get_qualifier_entry(mapping_qualifier, mapping_data: @mapping_data)
          if qualifier_entry.nil?
            raise MappingError, build_unknown_qualifier_issue(mapping_qualifier) if @mapping_strict

            return response_parameters
          end

          combined_map = build_snake_to_mqsc_map(qualifier_entry)
          mapped, issues = map_response_parameter_names(
            response_parameters, macro_lookup, combined_map, mapping_qualifier
          )

          raise MappingError, issues if @mapping_strict && !issues.empty?

          mapped
        end

        def build_snake_to_mqsc_map(qualifier_entry)
          request_key_map = qualifier_entry['request_key_map'] || {}
          response_key_map = qualifier_entry['response_key_map'] || {}

          response_lookup = {}
          if response_key_map.is_a?(Hash)
            response_key_map.each do |mqsc_key, snake_key|
              next unless mqsc_key.is_a?(String) && snake_key.is_a?(String)

              response_lookup[snake_key] ||= mqsc_key
            end
          end

          combined = response_lookup.dup
          if request_key_map.is_a?(Hash)
            request_key_map.each do |key, value|
              next unless key.is_a?(String) && value.is_a?(String)

              combined[key] = value
            end
          end
          combined
        end

        def map_where_keyword(where, mapping_qualifier, strict:, mapping_data:)
          parts = where.strip.split(nil, 2)
          keyword = parts[0]
          rest = parts[1] || ''

          qualifier_entry = get_qualifier_entry(mapping_qualifier, mapping_data: mapping_data)
          if qualifier_entry.nil?
            raise MappingError, build_unknown_qualifier_issue(mapping_qualifier) if strict

            return where
          end

          combined_map = build_snake_to_mqsc_map(qualifier_entry)
          mapped_keyword = combined_map[keyword]

          if mapped_keyword.nil?
            if strict
              raise MappingError, [
                MappingIssue.new(
                  direction: 'request', reason: 'unknown_key',
                  attribute_name: keyword, qualifier: mapping_qualifier
                )
              ]
            end
            mapped_keyword = keyword
          end

          rest.empty? ? mapped_keyword : "#{mapped_keyword} #{rest}"
        end

        def resolve_mapping_data(overrides, mode)
          if overrides
            MappingMerge.validate_mapping_overrides(overrides)
            if mode == MAPPING_OVERRIDE_REPLACE
              MappingMerge.validate_mapping_overrides_complete(MAPPING_DATA, overrides)
              return MappingMerge.replace_mapping_data(overrides)
            end
            return MappingMerge.merge_mapping_data(MAPPING_DATA, overrides)
          end
          MAPPING_DATA
        end

        def resolve_transport(credentials, transport)
          return transport if transport

          if credentials.is_a?(CertificateAuth)
            return NetHTTPTransport.new(
              client_cert: credentials.cert_path,
              client_key: credentials.key_path,
              ca_file: @tls_ca_file
            )
          end
          NetHTTPTransport.new(ca_file: @tls_ca_file)
        end
      end
    end
  end
end
