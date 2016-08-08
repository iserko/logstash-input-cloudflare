Gem::Specification.new do |s|
  s.name = 'logstash-input-cloudflare'
  s.version = '0.9.5'
  s.licenses = ['Apache License (2.0)']
  s.summary = 'This logstash input plugin fetches logs from Cloudflare using'\
              'their API'
  s.description = 'This gem is a logstash plugin required to be installed on'\
                  'top of the Logstash core pipeline using $LS_HOME/bin/plugin'\
                  ' install gemname. This gem is not a stand-alone program'
  s.authors = ['Igor Serko']
  s.email = 'igor.serko@gmail.com'
  s.homepage = 'https://github.com/iserko/logstash-input-cloudflare/'
  s.require_paths = ['lib']

  # Files
  s.files = Dir[
    'lib/**/*', 'spec/**/*', 'vendor/**/*', '*.gemspec', '*.md', 'CONTRIBUTORS',
    'Gemfile', 'LICENSE', 'NOTICE.TXT'
  ]
  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { 'logstash_plugin' => 'true', 'logstash_group' => 'input' }

  # Gem dependencies
  s.add_runtime_dependency 'logstash-core', '>= 2.0.0', '< 3.0.0'
  s.add_runtime_dependency 'logstash-codec-json', '>= 2.0.0', '< 3.0.0'
  s.add_development_dependency 'logstash-devutils', '>= 0.0.16', '< 0.1.0'
  s.add_development_dependency 'webmock', '>= 1.24.2', '< 1.25.0'
  s.add_development_dependency 'rubocop', '>= 0.36.0', '< 0.40.0'
end
