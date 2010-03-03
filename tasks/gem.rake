require 'hoe'

Hoe.plugin :debugging, :doofus, :git

HOE = Hoe.spec 'sqlite3-ruby' do
  developer           'Jamis Buck', 'jamis@37signals.com'
  developer           'Luis Lavena', 'luislavena@gmail.com'
  developer           'Aaron Patterson', 'aaron@tenderlovemaking.com'

  self.readme_file   = 'README.rdoc'
  self.history_file  = 'CHANGELOG.rdoc'
  self.extra_rdoc_files  = FileList['*.rdoc']

  spec_extras[:required_ruby_version]     = Gem::Requirement.new('> 1.8.5')
  spec_extras[:required_rubygems_version] = '>= 1.3.5'
  spec_extras[:extensions]                = ["ext/sqlite3/extconf.rb"]

  extra_dev_deps << ['rake-compiler', "~> 0.6.0"]

  clean_globs.push('**/test.db')
end

# vim: syntax=ruby
