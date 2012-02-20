# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "attachment_tap"

Gem::Specification.new do |s|
  s.name        = "attachment_tap"
  s.version     = Rack::AttachmentTap::VERSION
  s.authors     = ["elvuel"]
  s.email       = ["elvuel@gmail.com"]
  s.homepage    = "http://github.com/elvuel"
  s.summary     = %q{Attachment Tap}
  s.description = %q{Attachment Tap rack middleware}

  s.rubyforge_project = "attachment_tap"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  s.add_development_dependency "minitest"
  s.add_runtime_dependency "json"
end
