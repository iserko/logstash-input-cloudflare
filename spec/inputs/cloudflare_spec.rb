# encoding: utf-8
require 'logstash/devutils/rspec/spec_helper'
require 'logstash/inputs/cloudflare'
require 'webmock/rspec'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.before(:each) do
    stub_request(:get, /api.cloudflare.com/)
      .with(headers: { 'Accept' => '*/*', 'User-Agent' => 'Ruby' })
      .to_return(status: 200, body: 'stubbed response', headers: {})
  end
end

describe LogStash::Inputs::Cloudflare do
  let(:config) do
    {
      'auth_email' => 'test@test.com',
      'auth_key' => 'abcdefg',
      'domain' => 'example.com'
    }
  end
  it_behaves_like 'an interruptible input plugin'
end
