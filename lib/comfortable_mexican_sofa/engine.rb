require 'rubygems'
require 'comfortable_mexican_sofa'
require 'rails'
require 'bootstrap_form'
require 'active_link_to'
require 'paperclip'
require 'kramdown'
require 'jquery-rails'
require 'jquery-ui-rails'
require 'haml-rails'
require 'sass-rails'
require 'coffee-rails'
require 'codemirror-rails'
require 'kaminari'
require 'tinymce-rails'
require 'bootstrap-sass'

module ComfortableMexicanSofa
  class Engine < ::Rails::Engine
    config.autoload_paths += Dir["#{config.root}/app/presenters"]
  end
end
