require_relative 'dflow-import/dflow-import.rb'

require 'json'
require 'bundler'
Bundler.require(:default, ENV.fetch('RACK_ENV', 'development').to_sym)

# Only load reloader in development
require 'sinatra/reloader' if ENV.fetch('RACK_ENV', 'development') == 'development'

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
