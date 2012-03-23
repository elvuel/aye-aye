# encoding: utf-8
require 'stringio'
require 'tempfile'
require 'json'

module Rack
  class AyeAye

    VERSION = "1.2"

    # options :to(files)
    # :predators haunt? # for session or permission
    # :detector => a object respond_to chew!
    def initialize(app, options={})
      @app        = app
      @to         = options[:to] || 'files'
      @detector  = options[:detector]
      unless @detector.respond_to?(:chew!)
        raise ArgumentError, 'detector missing'
      end
    end

    # check the request whether has the ability to attachment file
    def call(env)
      if tap_in?(env)
        multipart_parsed = Rack::Multipart::Parser.new(env.dup).parse
        request = Rack::Request.new(env)
        request.params # this will implement the request.POST

        if multipart_parsed.nil?
          parsed_body = JSON.parse(request.body.read.to_s)
          request.body.rewind

          # remove params(those same as url params) from request body
          @app.class.routes[env['REQUEST_METHOD']].each do |route|
            if route.first =~ request.path
              params = route[1]
              params.each do |param|
                parsed_body.delete(param) if parsed_body[param]
              end if params
              break
            end
          end

          env['rack.input'] = StringIO.new(parsed_body.to_json)
          env['rack.request.form_input'] = env['rack.input']
          env['rack.request.form_hash'] = parsed_body
          env["CONTENT_LENGTH"] = parsed_body
        end

        env['rack.request.form_hash'] ||= {}

        # extract file fields and delete the fields key from form_hash
        fields = extract_file_fields!(
            env['rack.request.form_hash']
        ).flatten.compact

        if post?(env) && fields.empty?
          update_request_params!(env['rack.request.form_hash'], {@to => []})
        end

        if fields.any?
          # TODO
          # based on request content_type?
          json = @detector.chew!(fields)
          parsed_json = JSON.parse(json)
          if parsed_json.is_a?(Hash) && parsed_json["error"]
            return [502, {
                "Content-Type"  => "application/json",
                "Cache-Control" => "no-store"},
                    [json]
            ]
          end
          update_request_params!(
              env['rack.request.form_hash'],{@to => parsed_json}
          )
        end # fields.any?

        @app.class.routes[env['REQUEST_METHOD']].each do |route|
          if route.first =~ request.path
            params = route[1]
            params.each do |param|
              if env['rack.request.form_hash'][param]
                env['rack.request.form_hash'].delete(param)
              end
            end if params
            break
          end
        end

        new_input = env['rack.request.form_hash'].to_json
        env['rack.input'] = StringIO.new(new_input)
        env['rack.request.form_input'] = env['rack.input']

        env["CONTENT_LENGTH"] = env['rack.input'].read.to_s.size
        env['rack.input'].rewind

      end # tap_in?
      @app.call(env)
    end # call

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

    def extract_file_fields!(params)
      return nil unless params.is_a?(Hash)
      params.inject([]) do |fields, (k, v)|
        if v.is_a?(Hash)
          if v.has_key?(:filename) && v.has_key?(:type) &&
              v.has_key?(:name) && v.has_key?(:tempfile) &&
              v.has_key?(:head) && v[:tempfile].is_a?(Tempfile)
            v = params.delete(k) || v
            params.update({}) # make sure update params
            fields << v
          else
            fields << extract_file_fields!(v)
          end
        else
          fields << nil
        end
      end
    end

    def update_request_params!(params, hash)
      params.update(hash)
    end

  end # AyeAye
end # Rack