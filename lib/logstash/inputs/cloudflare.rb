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
  config :metadata_filepath,
         validate: :string, default: '/tmp/cf_logstash_metadata.json', required: false
  config :poll_time, validate: :number, default: 15, required: false
  config :start_from_secs_ago, validate: :number, default: 1200, required: false
  config :batch_size, validate: :number, default: 1000, required: false
  config :fields, validate: :array, default: DEFAULT_FIELDS, required: false

  public

  def register
    @host = Socket.gethostname
  end # def register

  def read_metadata
    # read the ray_id of the message which was parsed last
    metadata = {}
    if File.exist?(@metadata_filepath)
      content = File.read(@metadata_filepath).strip
      unless content.empty?
        begin
          metadata = JSON.parse(content)
        rescue JSON::ParserError
          metadata = {}
        end
      end
    end
    # make sure metadata contains all the keys we need
    %w(first_ray_id last_ray_id first_timestamp
       last_timestamp).each do |field|
      metadata[field] = nil unless metadata.key?(field)
    end
    metadata['default_start_time'] = \
      Time.now.getutc.to_i - @start_from_secs_ago
    metadata
  end # def read_metadata

  def write_metadata(metadata)
    File.open(@metadata_filepath, 'w') do |file|
      file.write(JSON.generate(metadata))
    end
  end # def write_metadata

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
      @logger.info("Received response from Cloudflare API (status_code: #{response.code})")
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

  def cf_params(metadata)
    params = {}
    # if we have ray_id, we use that as a starting point
    if metadata['last_ray_id']
      @logger.info("Previous ray_id detected: #{metadata['last_ray_id']}")
      params['start_id'] = metadata['last_ray_id']
      params['count'] = @batch_size
      metadata['first_ray_id'] = metadata['last_ray_id']
      metadata['first_timestamp'] = nil
    elsif metadata['last_timestamp']
      dt_tstamp = DateTime.strptime(metadata['last_timestamp'], '%s')
      @logger.info('last_timestamp from previous run detected: '\
                   "#{metadata['last_timestamp']} #{dt_tstamp}")
      params['start'] = metadata['last_timestamp'].to_i
      params['end'] = params['start'] + 120
      metadata['first_ray_id'] = nil
      metadata['first_timestamp'] = params['start']
    else
      @logger.info('last_timestamp or last_ray_id from previous run NOT set')
      params['start'] = metadata['default_start_time']
      params['end'] = params['start'] + 120
      metadata['first_ray_id'] = nil
      metadata['first_timestamp'] = params['start']
    end
    metadata['last_timestamp'] = nil
    metadata['last_ray_id'] = nil
    params
  end # def cf_params

  def cloudflare_data(zone_id, metadata)
    @logger.info("cloudflare_data metadata: '#{metadata}'")
    params = cf_params(metadata)
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
        metadata = read_metadata
        entries = cloudflare_data(zone_id, metadata)
        @logger.info("Received #{entries.length} events")
        entries.each do |entry|
          # skip the first ray_id because we already processed it
          # in the last run
          next if metadata['first_ray_id'] && \
                  entry['rayId'] == metadata['first_ray_id']
          event = LogStash::Event.new('host' => @host)
          fill_cloudflare_data(event, entry)
          decorate(event)
          queue << event
          metadata['last_ray_id'] = entry['rayId']
          # Cloudflare provides the timestamp in nanoseconds
          metadata['last_timestamp'] = entry['timestamp'] / 1_000_000_000
        end
        @logger.info(metadata)
        if metadata['first_timestamp']
          mod_tstamp = metadata['first_timestamp'].to_i + 120
        else
          mod_tstamp = nil
        end
        if !metadata['last_timestamp'] && metadata['first_timestamp'] && \
           mod_tstamp <= metadata['default_start_time']
          # we need to increment the timestamp by 2 minutes as we haven't
          # received any results in the last batch ... also make sure we
          # only do this if the end date is more than 10 minutes from the
          # current time
          @logger.info('Incrementing start timestamp by 120 seconds')
          metadata['last_timestamp'] = mod_tstamp
        else # if
          @logger.info("Waiting #{@poll_time} seconds before requesting data"\
                       'from Cloudflare again')
          (@poll_time * 2).times do
            sleep(0.5)
          end
        end
        write_metadata(metadata)
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
