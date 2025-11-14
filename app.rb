require 'json'
require 'bundler'
require 'semantic_logger'
Bundler.require(:default, ENV.fetch('RACK_ENV', 'development').to_sym)

# Only load reloader in development
require 'sinatra/reloader' if ENV.fetch('RACK_ENV', 'development') == 'development'

require_relative 'dflow-import/dflow_import'
require_relative 'lib/ecs_json_formatter'

SemanticLogger.default_level = :info
SemanticLogger.application = 'gupea-dflow-import'

formatter = if ENV.fetch('RACK_ENV', 'development') == 'development' then :color else EcsJsonFormatter.new end

SemanticLogger.add_appender(
  io: $stdout,
  formatter: formatter
)

class App < Sinatra::Base

   set :bind, '0.0.0.0'

   configure :development do
      register Sinatra::Reloader
      also_reload './app.rb'
      also_reload './**/*.rb'
   end

   get '/dflow_import/:id' do
      content_type :json
      DflowImport.run(params, self)
   end
end
