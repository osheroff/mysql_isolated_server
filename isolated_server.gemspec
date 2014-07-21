# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'isolated_server/version'

Gem::Specification.new do |spec|
  spec.name          = "isolated_server"
  spec.version       = IsolatedServer::VERSION
  spec.authors       = ["Ben Osheroff", "Gabe Martin-Dempesy"]
  spec.email         = ["ben@zendesk.com", "gabe@zendesk.com"]
  spec.description   = %q{A small library that allows you to easily spin up new local mysql servers for testing purposes.}
  spec.summary       = %q{A small library that allows you to easily spin up new local mysql servers for testing purposes.}
  spec.homepage      = "http://github.com/gabetax/isolated_server"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "appraisal"
end
