source 'http://rubygems.org'

gemspec

gem "transitions", :require => ["transitions", "active_model/transitions"]
gem 'responders', '~> 2.0'

group :development do
  gem 'awesome_print'
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'quiet_assets'
end

group :test do
  gem 'sqlite3',                          :platform => [:ruby, :mswin, :mingw]
  gem 'jdbc-sqlite3',                     :platform => :jruby
  gem 'activerecord-jdbcsqlite3-adapter', :platform => :jruby
  gem 'mocha',      :require => false
  gem 'coveralls',  :require => false
  gem 'timecop'
  gem 'rspec-core'
  gem 'factory_bot_rails'
  gem 'database_cleaner'
  gem 'faker', '~> 1.7'
  gem 'pry-byebug'
  gem 'nokogiri', '~>1.6.0'
end
