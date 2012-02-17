# encoding: utf-8

require 'minitest/autorun'
require 'tempfile'
require 'json'
require File.expand_path('../../lib/rack/attachment_tap', __FILE__)

class FakeApp
  def call(env) end
end

class FakeSurrogate
  def self.ship!(files)
    "{'id':'98d41a087efa9aa3b9ceb9d0','original':'/path/to/file'}"
  end

  def self.discharge!(files)
    '{}'
  end
end

describe Rack::AttachmentTap do

  describe '#initialize' do
    it "raise ArgumentError if surrogate not respond to ship!" do
      lambda { Rack::AttachmentTap.new(FakeApp.new) }.must_raise ArgumentError
      lambda { Rack::AttachmentTap.new(FakeApp.new, { :surrogate => "123" }) }
        .must_raise ArgumentError
      obj, obj1, obj2 = "0", "1", "2"
      def obj.ship!;end
      def obj1.discharge!;end
      def obj2.ship!;end
      def obj2.discharge!;end
      lambda { Rack::AttachmentTap.new(FakeApp.new, { :surrogate => obj }) }
        .must_raise ArgumentError
      lambda { Rack::AttachmentTap.new(FakeApp.new, { :surrogate => obj1 }) }
        .must_raise ArgumentError
      Rack::AttachmentTap.new(FakeApp.new, { :surrogate => obj2 })
        .must_be_kind_of Rack::AttachmentTap
    end
  end

  describe '#post?' do
    before do
      @key = 'REQUEST_METHOD'
      @method = :post?
    end
    it 'request method is POST should return true' do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      atap.send(@method,  @key => 'POST').must_equal true
    end

    it 'require method not POST should return false' do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      atap.send(@method, @key => "post").must_equal false
    end
  end

  describe '#put?' do
    before do
      @key = 'REQUEST_METHOD'
      @method = :put?
    end
    it 'request method is PUT should return true' do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      atap.send(@method,  @key => 'PUT').must_equal true
    end

    it 'require method not PUT should return false' do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      atap.send(@method, @key => "put").must_equal false
    end
  end

  describe '#content_type_raw?' do
    before do
      @key = 'CONTENT_TYPE'
      @method = :content_type_raw?
    end

    it 'content type is multipart/form-data should return true' do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      atap.send(@method,  @key => 'multipart/form-data;12345').must_equal true
    end

    it 'content type is application/x-www-form-urlencoded should return true' do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      atap.send(@method,  @key => 'application/x-www-form-urlencoded;12345')
        .must_equal true
    end

    it 'return false' do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      atap.send(@method, @key => 'text/html').must_equal false
    end
  end

  describe '#has_content?' do
    before do
      @key = 'CONTENT_LENGTH'
      @method = :has_content?
    end

    it 'content length gt 0 return true' do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      atap.send(@method,  @key => '123').must_equal true
    end

    it 'content length lt 0 return true' do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      atap.send(@method, @key => '0').must_equal false
    end
  end

  describe '#extract_file_fields' do
    before do
      @method = :extract_file_fields
    end
    it "return nil if argument is not a Hash" do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      atap.send(@method, 123).must_be_nil
    end

    it "should return a empty array if not contains FILE field" do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      fields = atap.send(@method,
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
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      fields = atap.send(@method, {
          'text' => 'info', 'some' => 'some',
          'file1' => file1, 'file2' => file2}
      )
      fields.must_be_kind_of Array
      fields = fields.flatten.compact
      fields.size.must_equal 2
      [file1, file2].each { |f| fields.delete f }
      fields.empty?.must_equal true
    end
  end

  describe '#file_field_keys' do
    before do
      @method = :file_field_keys
    end

    it "should return a Array" do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      ary = [{:name => 'first'}, {:name => 'second'}]
      keys = atap.send(@method, ary)
      keys.must_be_kind_of Array
      keys.size.must_equal 2
      keys.must_equal ['first', 'second']
    end

    it "should return a unique Array" do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      ary = [{:name => 'first'}, {:name => 'second'}, {:name => 'first[file]'}]
      keys = atap.send(@method, ary)
      keys.must_be_kind_of Array
      keys.size.must_equal 2
      keys.must_equal ['first', 'second']
    end
  end

  describe '#delete_file_fields!' do
    before do
      @method = :delete_file_fields!
    end

    it "should delete nothing" do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      env = { 'rack.request.form_hash' => {'text' => 'text', 'name' => 'ok' } }
      atap.send(@method, env, [])
      env['rack.request.form_hash'].has_key?('text').must_equal true
      env['rack.request.form_hash'].has_key?('name').must_equal true
    end

    it "should delete the specify key" do
      atap = Rack::AttachmentTap.new(FakeApp.new, {:surrogate => FakeSurrogate })
      env = { 'rack.request.form_hash' => {'text' => 'text', 'name' => 'ok' } }
      atap.send(@method, env, ['text'])
      env['rack.request.form_hash'].has_key?('text').must_equal false
      env['rack.request.form_hash'].has_key?('name').must_equal true
    end
  end

  describe '#call' do
    before do

    end
  end

end