require 'sinatra'
require 'json'
require_relative './stateless'

module Gruesome
  class GruesomeWeb < Sinatra::Base
    get '/' do
      gruesome = Gruesome::Stateless.new
      state = gruesome.start(:zork)

      content_type :json

      { :output => state[:out],
        :memory => state[:base64memory]
      }.to_json
    end

    post '/' do
      gruesome = Gruesome::Stateless.new
      params = JSON.parse(request.body.read)

      state = gruesome.continue(:zork, params["command"], params["memory"])

      content_type :json
      { :output => state[:out],
        :memory => state[:base64memory]
      }.to_json
    end
  end
end
