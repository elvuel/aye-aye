# encoding: utf-8
require 'minitest/autorun'
require 'ostruct'
require 'rack'
require 'mocha'

require File.expand_path('../../lib/rack/aye_aye', __FILE__)

class FakeApp
  def call(env) end
  def self.routes
    {
        'PUT' => [], 'POST' => []
    }
  end
end

class FakeDetector
  def self.chew!(files=nil)
    [
        {
            :id => '98d41a087efa9aa3b9ceb9d0',
            :original => 'path/to/file'
        }
    ].to_json
  end
end

class FakeDetectorSick
  def self.chew!(files)
    { error: 'file attach exception with md5s' }.to_json
  end
end

describe Rack::AyeAye do

  describe '#initialize' do
    it "raise ArgumentError if surrogate not respond to chew!" do
      lambda { Rack::AyeAye.new(FakeApp.new) }.must_raise ArgumentError
      lambda { Rack::AyeAye.new(FakeApp.new, { :detector => "123" }) }
      .must_raise ArgumentError
      obj, obj1, obj2 = "0", "1", "2"
      def obj2.chew!;end
      lambda { Rack::AyeAye.new(FakeApp.new, { :detector => obj }) }
      .must_raise ArgumentError
      lambda { Rack::AyeAye.new(FakeApp.new, { :detector => obj1 }) }
      .must_raise ArgumentError
      Rack::AyeAye.new(FakeApp.new, { :detector => obj2 })
      .must_be_kind_of Rack::AyeAye
    end
  end # initialize

  describe '#post?' do
    before do
      @key = 'REQUEST_METHOD'
      @method = :post?
    end
    it 'request method is POST should return true' do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      aye_aye.send(@method,  @key => 'POST').must_equal true
    end

    it 'require method not POST should return false' do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      aye_aye.send(@method, @key => "post").must_equal false
    end
  end # post?

  describe '#put?' do
    before do
      @key = 'REQUEST_METHOD'
      @method = :put?
    end
    it 'request method is PUT should return true' do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      aye_aye.send(@method,  @key => 'PUT').must_equal true
    end

    it 'require method not PUT should return false' do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      aye_aye.send(@method, @key => "put").must_equal false
    end
  end # put?

  describe '#content_type_raw?' do
    before do
      @key = 'CONTENT_TYPE'
      @method = :content_type_raw?
    end

    it 'content type is multipart/form-data should return true' do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      aye_aye.send(@method,  @key => 'multipart/form-data;12345')
      .must_equal true
    end

    it 'content type is application/x-www-form-urlencoded should return true' do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      aye_aye.send(@method,  @key => 'application/x-www-form-urlencoded;12345')
      .must_equal true
    end

    it 'return false' do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      aye_aye.send(@method, @key => 'text/html').must_equal false
    end
  end # content_type_raw?

  describe '#has_content?' do
    before do
      @key = 'CONTENT_LENGTH'
      @method = :has_content?
    end

    it 'content length gt 0 return true' do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      aye_aye.send(@method,  @key => '123').must_equal true
    end

    it 'content length lt 0 return true' do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      aye_aye.send(@method, @key => '0').must_equal false
    end
  end # has_content?

  describe '#extract_file_fields!' do
    before do
      @method = :extract_file_fields!
    end
    it "return nil if argument is not a Hash" do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      aye_aye.send(@method, 123).must_be_nil
    end

    it "should return a empty array if not contains FILE field" do
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      fields = aye_aye.send(@method,
                            { 'text' => '123', 'not_file' => {"not" => "yes"} })
      fields.must_be_kind_of Array
      fields.flatten.compact.empty?.must_equal true
    end

    it "should return the file fields" do
      file1 = { :filename => 'file 1', :type => 'type 1',
                :name => 'name 1', :head => 'head 1',
                :tempfile => ::Tempfile.new('tempfile1.')
      }
      file2 = { :filename => 'file 2', :type => 'type 2',
                :name => 'name 2', :head => 'head 2',
                :tempfile => ::Tempfile.new('tempfile2.')
      }
      file3 = { :filename => 'file 3', :type => 'type 3',
                :name => 'name 3', :head => 'head 3',
                :tempfile => ::Tempfile.new('tempfile3.')
      }
      aye_aye = Rack::AyeAye.new(FakeApp.new, {:detector => FakeDetector })
      args = {
          'text' => 'info', 'some' => 'some',
          'file1' => file1, 'file2' => file2,
          'file3' => { '0' => file3, '1' => 1}
      }
      fields = aye_aye.send(@method, args)
      fields.must_be_kind_of Array
      fields = fields.flatten.compact
      fields.size.must_equal 3
      [file1, file2, file3].each { |f| fields.delete f }
      fields.empty?.must_equal true
      args.has_key?('file1').must_equal false
      args.has_key?('file2').must_equal false
      args.has_key?('file3').must_equal true
      args["file3"].has_key?('0').must_equal false
      args["file3"].has_key?('1').must_equal true
    end
  end # extract_file_fields

  describe '#call' do
    before do

      @file1 = {:filename => 'file 1', :type => 'type 1',
                :name => 'name 1', :head => 'head 1',
                :tempfile => ::Tempfile.new('tempfile1.')
      }
      @file2 = {:filename => 'file 2', :type => 'type 2',
                :name => 'name 2', :head => 'head 2',
                :tempfile => ::Tempfile.new('tempfile2.')
      }

      @env_post = {
          'REQUEST_METHOD' => 'POST',
          'CONTENT_TYPE' => 'multipart/form-data; 0123456789abcdef',
          'CONTENT_LENGTH' => '123',
          'rack.request.form_hash' => {
              'name' => 'post aye_aye'
          }
      }

      @env_put = {
          'REQUEST_METHOD' => 'PUT',
          'CONTENT_TYPE' => 'multipart/form-data; 0123456789abcdef',
          'CONTENT_LENGTH' => '123',
          'rack.request.form_hash' => {
              'name' => 'put aye_aye'
          }
      }
    end

    describe 'POST request' do

      before do
        request = OpenStruct.new(
            body: StringIO.new(@env_post['rack.request.form_hash'].to_json)
        )
        Rack::Request.stubs(:new).returns(request)
        Rack::Multipart::Parser.any_instance.stubs(:parse).returns(nil)
      end

      describe 'no file fields' do
        it 'update the request form hash to a empty array' do
          @aye_aye = Rack::AyeAye.new(FakeApp.new, {
              :detector => FakeDetector
          })
          @env_post['rack.input'].must_be_nil

          @env_post['rack.request.form_hash'].has_key?('files').must_equal false
          @aye_aye.call(@env_post)
          @env_post['rack.request.form_hash'].has_key?('files').must_equal true
          files = @env_post['rack.request.form_hash']['files']
          files.must_be_kind_of Array
          files.must_be_empty

          @env_post['rack.input'].must_be_kind_of StringIO
          new_input = JSON.parse(@env_post['rack.request.form_input'].read.to_s)
          new_input.must_be_kind_of Hash
          new_input["name"].must_equal "post aye_aye"
          new_input["files"].must_equal []
          @env_post["CONTENT_LENGTH"].wont_equal '123'
          @env_post["CONTENT_LENGTH"]
          .must_equal "{\"name\":\"post aye_aye\",\"files\":[]}".size
        end
      end # no file fields
    end # POST request

    describe 'PUT request' do

      before do
        request = OpenStruct.new(
            body: StringIO.new(@env_put['rack.request.form_hash'].to_json)
        )
        Rack::Request.stubs(:new).returns(request)
        Rack::Multipart::Parser.any_instance.stubs(:parse).returns(nil)
      end

      describe 'no file fields' do
        it 'wont update the form_hash files' do
          @aye_aye = Rack::AyeAye.new(FakeApp.new, {
              :detector => FakeDetector
          })
          @env_put['rack.request.form_hash'].has_key?('files').must_equal false
          @aye_aye.call(@env_put)
          @env_put['rack.request.form_hash'].has_key?('files').must_equal false

          @env_put['rack.input'].must_be_kind_of StringIO
          new_input = JSON.parse(@env_put['rack.request.form_input'].read.to_s)
          new_input.must_be_kind_of Hash
          new_input["name"].must_equal "put aye_aye"
          @env_put["CONTENT_LENGTH"].wont_equal '123'
          @env_put["CONTENT_LENGTH"]
          .must_equal "{\"name\":\"put aye_aye\"}".size
        end
      end # no file fields
    end # PUT request

    describe "got attachments" do
      before do
        Rack::Request.stubs(:new).returns(OpenStruct.new)
        Rack::Multipart::Parser.any_instance.stubs(:parse).returns("not-nil")

        @env_post['rack.request.form_hash']
        .update('file1' => @file1, 'file2' => @file2)
        @env_put['rack.request.form_hash']
        .update('file1' => @file1, 'file2' => @file2)
      end

      it "should test" do
        [@env_put, @env_post].each do |env|
          aye_aye = Rack::AyeAye.new(FakeApp.new, {
              :detector => FakeDetector
          })
          env['rack.request.form_hash'].has_key?('files').must_equal false
          aye_aye.call(env)
          env['rack.request.form_hash'].has_key?('files').must_equal true
          files = env['rack.request.form_hash']['files']
          files.must_be_kind_of Array
          files.wont_be_empty

          env['rack.input'].must_be_kind_of StringIO
          new_input = JSON.parse(env['rack.request.form_input'].read.to_s)

          new_input.must_be_kind_of Hash
          req_method = env["REQUEST_METHOD"].downcase
          new_input["name"].must_equal "#{req_method} aye_aye"
          new_input["files"].must_be_kind_of Array
          new_input["files"].wont_be_empty

          file_hash = JSON.parse(FakeDetector.chew!).first
          new_input["files"].first
          .must_equal file_hash

          env["CONTENT_LENGTH"].wont_equal '123'
          new_content = {
              name: "#{req_method} aye_aye",
              files: [JSON.parse(FakeDetector.chew!).first]
          }.to_json
          env["CONTENT_LENGTH"].must_equal new_content.size
        end
      end
    end # got attachments

    describe 'chew! error' do
      before do
        Rack::Request.stubs(:new).returns(OpenStruct.new)
        Rack::Multipart::Parser.any_instance.stubs(:parse).returns("not-nil")
        @env_post['rack.request.form_hash']
        .update('file1' => @file1, 'file2' => @file2)
        @env_put['rack.request.form_hash']
        .update('file1' => @file1, 'file2' => @file2)
      end

      it "return 502 with chew! error" do
        [@env_post, @env_put].each { |call_env|
          aye_aye = Rack::AyeAye.new(FakeApp.new, {
              :detector => FakeDetectorSick
          })
          result = aye_aye.call(call_env)
          result.must_be_kind_of Array
          result.first.must_equal 502
        }
      end
    end # chew! error

  end # call
end # Rack::AyeAye