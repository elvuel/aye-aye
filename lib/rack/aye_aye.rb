# encoding: utf-8
require 'tempfile'
require 'json'

module Rack
  class AyeAye

    VERSION = "1.1"

    # options :to(files) :path_rule?
    # :request_validator? session or permission
    # :surrogate => a object respond_to ship! discharge!
    def initialize(app, options={})
      @app      = app
      @to       = options[:to] || 'files'
      @surrogate = options[:surrogate]
      unless @surrogate.respond_to?(:ship!) && @surrogate.respond_to?(:discharge!)
        raise ArgumentError, 'surrogate missing'
      end
    end

    # check the request whether has the ability to attachment file
    def call(env)
      if tap_in?(env)
        if env['rack.input'].is_a?(Tempfile)
          env['rack.input'] = StringIO.new(env['rack.input'])
        end

        env['rack.request.form_input'] = env['rack.input']
        env['rack.request.form_hash'] ||= {}

        fields = extract_file_fields(env['rack.request.form_hash']).
            flatten.compact

        if fields.empty?
          update_request_params!(env['rack.request.form_hash'], {@to => '[]'})
        else
          # TODO
          # based on request content_type?
          json = @surrogate.ship!(fields)
          parsed_json = JSON.parse(json)
          if parsed_json.is_a?(Hash) && parsed_json["error"]
            return [502, {
                "Content-Type" => "application/json",
                "Cache-Control" => "no-store" },
                [json]
            ]
          end

          # TODO
          # put? pending
          # @surrogate.ship!(fields)
          #         #?[AFTER] HTTP_HEADER => "HTTP_RESOURCE_ORIGINAL_FILES"
          #
          # @surrogate.discharge!(old_files_to_be_deleted)
          # send this to delay job or resque # return nothing

          fields_should_be_deleted = file_field_keys(fields)
          delete_file_fields!(env, fields_should_be_deleted)
          update_request_params!(env['rack.request.form_hash'], {@to => json})
        end
      end
      @app.call(env)
    end

    protected

    def tap_in?(env)
      request_method_raw?(env) &&
          content_type_raw?(env) &&
          has_content?(env) &&
          session_scoped?(env)
    end

    def post?(env)
      env['REQUEST_METHOD'] == "POST"
    end

    def put?(env)
      env['REQUEST_METHOD'] == "PUT"
    end

    def request_method_raw?(env)
      post?(env)# || put?(env)
    end

    def content_type_raw?(env)
      case env["CONTENT_TYPE"]
        when %r{^multipart/form-data}, %r{^application/x-www-form-urlencoded}
          true
        else
          false
      end
    end

    def has_content?(env)
      env["CONTENT_LENGTH"].to_i > 0
    end

    def session_scoped?(env)
      # pending
      # request = Rack::Request.new(env) | validator
      # request.session.inspect
      true
    end

    def extract_file_fields(params)
      return nil unless params.is_a?(Hash)
      params.inject([]) do |fields, (k, v)|
        if v.is_a?(Hash)
          if v.has_key?(:filename) && v.has_key?(:type) &&
              v.has_key?(:name) && v.has_key?(:tempfile) &&
              v.has_key?(:head) && v[:tempfile].is_a?(Tempfile)
            fields << v
          else
            fields << extract_file_fields(v)
          end
        else
          fields << nil
        end
      end
    end

    def file_field_keys(fields)
      fields.collect {
          |field| field[:name].split("[").first.to_s
      }.uniq
    end

    def delete_file_fields!(env, fields)
      fields.each do |field|
        env['rack.request.form_hash'].delete(field)
      end
    end

    def update_request_params!(params, hash)
      params.update(hash)
    end

  end # AyeAye
end # Rack
