# encoding: utf-8
require 'date'
require 'json'
require 'logstash/inputs/base'
require 'logstash/namespace'
require 'net/http'
require 'socket' # for Socket.gethostname

class CloudflareAPIError < StandardError
  attr_accessor :url
  attr_accessor :errors
  attr_accessor :success
  attr_accessor :status_code

  def initialize(url, response, content)
    begin
      json_data = JSON.parse(content)
    rescue JSON::ParserError
      json_data = {}
    end
    @url = url
    @success = json_data.fetch('success', false)
    @errors = json_data.fetch('errors', [])
    @status_code = response.code
  end # def initialize
end # class CloudflareAPIError

def response_body(response)
  return '' unless response.body
  return response.body.strip unless response.header['Content-Encoding'].eql?('gzip')
  sio = StringIO.new(response.body)
  gz = Zlib::GzipReader.new(sio)
  gz.read.strip
end # def response_body

def parse_content(content)
  return [] if content.empty?
  lines = []
  content.split("\n").each do |line|
    line = line.strip
    next if line.empty?
    begin
      lines << JSON.parse(line)
    rescue JSON::ParserError
      @logger.error("Couldn't parse JSON out of '#{line}'")
      next
    end
  end
  lines
end # def parse_content

def read_file(filepath)
  # read the ray_id of the message which was parsed last
  return nil unless File.exist?(filepath)
  content = File.read(filepath).strip
  return nil unless content.empty?
  content
end # def read_file

def write_file(filepath, content)
  File.open(filepath, 'w') do |file|
    file.write(content)
  end
end # def write_file

# you can get the list of fields in the documentation provided
# by Cloudflare
DEFAULT_FIELDS = [
  'timestamp', 'zoneId', 'ownerId', 'zoneName', 'rayId', 'securityLevel',
  'client.ip', 'client.country', 'client.sslProtocol', 'client.sslCipher',
  'client.deviceType', 'client.asNum', 'clientRequest.bytes',
  'clientRequest.httpHost', 'clientRequest.httpMethod', 'clientRequest.uri',
  'clientRequest.httpProtocol', 'clientRequest.userAgent',
  'edgeResponse.status', 'edgeResponse.bytes'
].freeze

class LogStash::Inputs::Cloudflare < LogStash::Inputs::Base
  config_name 'cloudflare'

  default :codec, 'json'

  config :auth_email, validate: :string, required: true
  config :auth_key, validate: :string, required: true
  config :domain, validate: :string, required: true
  config :cf_rayid_filepath,
         validate: :string, default: '/tmp/previous_cf_rayid', required: false
  config :cf_tstamp_filepath,
         validate: :string, default: '/tmp/previous_cf_tstamp', required: false
  config :poll_time, validate: :number, default: 15, required: false
  config :default_age, validate: :number, default: 1200, required: false
  config :fields, validate: :array, default: DEFAULT_FIELDS, required: false

  public

  def register
    @host = Socket.gethostname
  end # def register

  def cloudflare_api_call(endpoint, params, multi_line = false)
    uri = URI("https://api.cloudflare.com/client/v4#{endpoint}")
    uri.query = URI.encode_www_form(params)
    @logger.info('Sending request to Cloudflare')
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Get.new(
        uri.request_uri,
        'Accept-Encoding' => 'gzip',
        'X-Auth-Email' => @auth_email,
        'X-Auth-Key' => @auth_key
      )
      response = http.request(request)
      content = response_body(response)
      if response.code != '200'
        raise CloudflareAPIError.new(uri.to_s, response, content),
              'Error calling Cloudflare API'
      end
      lines = parse_content(content)
      return lines if multi_line
      return lines[0]
    end
  end # def cloudflare_api_call

  def cloudflare_zone_id(domain)
    params = { status: 'active' }
    response = cloudflare_api_call('/zones', params)
    response['result'].each do |zone|
      return zone['id'] if zone['name'] == domain
    end
    raise "No zone with domain #{domain} found"
  end # def cloudflare_zone_id

  def cf_params(ray_id, tstamp)
    params = {}
    # timestamp should always have priority over ray id due to the
    # API not supporting `count`
    if tstamp && !tstamp.empty?
      dt_tstamp = DateTime.strptime(tstamp, '%s')
      @logger.info("Previous timestamp detected: #{tstamp} #{dt_tstamp}")
      params['start'] = tstamp.to_i
      params['end'] = tstamp.to_i + 120
    elsif ray_id && !ray_id.empty?
      @logger.info("Previous ray_id detected: #{ray_id}")
      params['start_id'] = ray_id
      params['count'] = 100 # not supported in the API yet
    else
      @logger.info('Previous tstamp or ray_id NOT detected')
      params['start'] = Time.now.getutc.to_i - @default_age
      params['end'] = params['start'] + 120
    end
    params
  end # def cf_params

  def cloudflare_data(zone_id, ray_id, tstamp)
    params = cf_params(ray_id, tstamp)
    @logger.info("Using params #{params}")
    begin
      entries = cloudflare_api_call("/zones/#{zone_id}/logs/requests",
                                    params, multi_line: true)
    rescue CloudflareAPIError => err
      err.errors.each do |error|
        @logger.error("Cloudflare error code: #{error['code']}: "\
                      "#{error['message']}")
      end
      entries = []
    end
    return entries unless entries.empty?
    @logger.info('No entries returned from Cloudflare')
    entries
  end # def cloudflare_data

  def fill_cloudflare_data(event, data)
    fields.each do |field|
      value = Hash[data]
      field.split('.').each do |field_part|
        value = value.fetch(field_part, {})
      end
      event[field.tr('.', '_')] = value
    end
  end # def fill_cloudflare_data

  def run(queue)
    @logger.info('Starting cloudflare run')
    zone_id = cloudflare_zone_id(@domain)
    @logger.info("Resolved zone ID #{zone_id} for domain #{@domain}")
    until stop?
      begin
        ray_id = read_file(@cf_rayid_filepath)
        tstamp = read_file(@cf_tstamp_filepath)
        entries = cloudflare_data(zone_id, ray_id, tstamp)
        new_ray_id = nil
        new_tstamp = nil
        @logger.info("Received #{entries.length} events")
        entries.each do |entry|
          event = LogStash::Event.new('host' => @host)
          fill_cloudflare_data(event, entry)
          decorate(event)
          queue << event
          new_ray_id = entry['rayId']
          # Cloudflare provides the timestamp in nanoseconds
          new_tstamp = entry['timestamp'] / 1_000_000_000
        end
        @logger.info("new_tstamp #{new_tstamp}")
        if !new_tstamp && tstamp && !tstamp.empty?
          # we need to increment the timestamp by 2 minutes as we haven't
          # received any results in the last batch ... also make sure we
          # only do this if the end date is more than 10 minutes from the
          # current time
          max_time = Time.now.getutc.to_i - @default_age
          mod_tstamp = tstamp.to_i + 120
          unless mod_tstamp > max_time
            @logger.info('Incrementing start timestamp by 120 seconds')
            new_tstamp = mod_tstamp
          end
        else # if new_tstamp is set, we received results
          @logger.info("Waiting #{@poll_time} seconds before requesting data"\
                       'from Cloudflare again')
          (@poll_time * 2).times do
            sleep(0.5)
          end
        end
        write_file(@cf_rayid_filepath, new_ray_id)
        write_file(@cf_tstamp_filepath, new_tstamp)
      rescue => exception
        break if stop?
        @logger.error(exception.class)
        @logger.error(exception.message)
        @logger.error(exception.backtrace.join("\n"))
        raise(exception)
      end
    end # until loop
  end # def run
end # class LogStash::Inputs::Cloudflare
