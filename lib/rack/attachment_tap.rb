# encoding: utf-8
require 'tempfile'

module Rack
  class AttachmentTap

    VERSION = "1.0".freeze

    # options :to(files) :path_rule?
    # :request_validator? session or permission
    # :mandator => a object respond_to create_for
    def initialize(app, options={})
      @app      = app
      @to       = options[:to] || 'files'
      @mandator = options[:mandator]
    end

    # check the request whether has the ability to attachment file
    def call(env)
      if tap_in?(env)
        if env['rack.input'].is_a?(Tempfile)
          env['rack.input'] = StringIO.new(env['rack.input'])
        end

        env['rack.request.form_input'] = env['rack.input']
        env['rack.request.form_hash'] ||= {}
        env['rack.request.query_hash'] ||= {}

        fields = extract_file_fields(env['rack.request.form_hash']).
                  flatten.compact

        # TODO mandator
        json = '[]'
        #json = if post?
        #  @mandator.create_for!(fields)#
        #elsif put?
        #  @mandator.create_for(fields)
        # [AFTER] HTTP_HEADER => "HTTP_RESOURCE_ORIGINAL_FILES"
        #  send this to delay job or resque
        #end

        fields_should_be_deleted = fields.collect {
            |field| field[:name].split("[").first.to_s
        }.uniq

        delete_file_fields!(env, fields_should_be_deleted)

        update_request_params!(env['rack.request.form_hash'], { @to => json })

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
      post?(env) || put?(env)
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

    def delete_file_fields!(env, fields)
      fields.each do |field|
        env['rack.request.form_hash'].delete(field)
      end
    end

    def update_request_params!(params, hash)
      params.update(hash)
    end

  end # AttachmentTap
end # Rack
