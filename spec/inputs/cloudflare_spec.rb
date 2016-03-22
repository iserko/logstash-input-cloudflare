# encoding: utf-8
require 'json'
require 'logstash/devutils/rspec/spec_helper'
require 'logstash/inputs/cloudflare'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

ZONE_LIST_RESPONSE = {
  'result' => [
    'id' => 'zoneid',
    'name' => 'example.com'
  ]
}.freeze

LOGS_RESPONSE = {
}.freeze

HEADERS = {
  'Accept' => '*/*', 'Accept-Encoding' => 'gzip',
  'User-Agent' => 'Ruby', 'X-Auth-Email' => 'test@test.com',
  'X-Auth-Key' => 'abcdefg'
}.freeze

RSpec.configure do |config|
  config.before(:each) do
    stub_request(:get, 'https://api.cloudflare.com/client/v4/zones?status=active')
      .with(headers: HEADERS)
      .to_return(status: 200, body: ZONE_LIST_RESPONSE.to_json, headers: {})
    stub_request(:get, /api.cloudflare.com\/client\/v4\/zones\/zoneid\/logs\/requests.*/)
      .with(headers: HEADERS)
      .to_return(status: 200, body: LOGS_RESPONSE.to_json, headers: {})
  end
end

RSpec.describe LogStash::Inputs::Cloudflare do
  let(:config) do
    {
      'auth_email' => 'test@test.com',
      'auth_key' => 'abcdefg',
      'domain' => 'example.com'
    }
  end
  it_behaves_like 'an interruptible input plugin'
end
