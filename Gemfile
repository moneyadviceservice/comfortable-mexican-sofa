source 'http://rubygems.org'

gemspec

ruby '2.5.3'

gem "transitions", :require => ["transitions", "active_model/transitions"]
gem 'responders', '~> 2.0'

group :development do
  gem 'awesome_print'
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'quiet_assets'
end

group :test do
  gem 'activerecord-jdbcsqlite3-adapter', :platform => :jruby
  gem 'coveralls',  :require => false
  gem 'brakeman', require: false
  gem 'danger', require: false
  gem 'danger-rubocop', require: false
  gem 'database_cleaner'
  gem 'factory_bot_rails'
  gem 'faker', '~> 1.7'
  gem 'jdbc-sqlite3', :platform => :jruby
  gem 'mocha', :require => false
  gem 'mysql2', '~> 0.3.18'
  gem 'nokogiri', '~>1.6.0'
  gem 'pry-byebug'
  gem 'rspec-core'
  gem 'timecop'
  gem 'tzinfo-data'
end
