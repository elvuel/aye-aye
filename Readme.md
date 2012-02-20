# Attachment tap
## USAGE
  * gem build attachment_tap.gemspec
  * gem install attachemnt_tap-VERSION.gem
  * gem "attachment_tap", require: 'rack/attachment_tap'
  * use Rack::AttachmentTap, :surrogate => Surrogate[,:to => 'files']


## Surrogate Example


**gem "rest-client"**
**gem "multipart-post"**

    require 'net/http/post/multipart'

    class Surrogate

      def self.ship!(files)
        upload_files_hash = files.each_with_index.inject({}) do |hash, (item, index)|
          hash[index.to_s] = UploadIO.new(File.new(item[:tempfile].path,"rb"),
                                          item[:type], item[:filename])
          hash
        end
        req = RestClient.post("http://localhost:3001/",{
                 files: upload_files_hash
                },
                content_type: :json, accept: :json)
        req.body
      rescue Exception => e
        { :error => e.message }.to_json
      end

      def self.discharge!(files)

      end

    end
