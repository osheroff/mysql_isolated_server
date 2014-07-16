# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'isolated_server/version'

Gem::Specification.new do |gem|
  gem.name          = "isolated_server"
  gem.version       = IsolatedServer::VERSION
  gem.authors       = ["Ben Osheroff", "Gabe Martin-Dempesy"]
  gem.email         = ["ben@zendesk.com", "gabe@zendesk.com"]
  gem.description   = %q{A small library that allows you to easily spin up new local mysql servers for testing purposes.}
  gem.summary       = %q{A small library that allows you to easily spin up new local mysql servers for testing purposes.}
  gem.homepage      = "http://github.com/gabetax/isolated_server"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
end
