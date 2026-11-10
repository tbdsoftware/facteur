# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name          = 'facteur'
  s.version       = '0.4.0'
  s.summary       = 'Log and get analytics for emails you send'
  s.authors       = ['Philippe Durix']
  s.email         = 'philippe.durix@me.com'
  s.files         = Dir['{app,config,lib}/**/*', 'README.md']
  s.require_path  = 'lib'
  s.homepage      = ''
  s.license       = 'MIT'

  s.required_ruby_version = '>= 3.1'

  s.add_dependency 'oj'
  s.add_dependency 'rails', '>= 7.0'
  s.add_dependency 'sidekiq', '>= 6.5'
end
