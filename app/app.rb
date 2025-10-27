require_relative 'import-dflow/import_dflow.rb'

require 'json'

require 'sinatra/base'
require "sinatra/reloader"
require 'bundler'
Bundler.require ENV['APP_ENV'].to_sym

class App < Sinatra::Base

   set :bind, '0.0.0.0'

   configure :development do
      register Sinatra::Reloader
      also_reload './app.rb'
      also_reload './**/*.rb'
   end

   get '/dflow_import/:id' do
      content_type :json
      ImportDflow.run(params, self)
   end

end

