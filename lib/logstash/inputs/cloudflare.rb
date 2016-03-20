# encoding: utf-8
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
    @success = json_data.fetch('success')
    @errors = json_data.fetch('errors', [])
    @status_code = response.code
  end
end

class LogStash::Inputs::Cloudflare < LogStash::Inputs::Base
  config_name 'cloudflare'

  default :codec, 'json'

  config :auth_email, validate: :string, required: true
  config :auth_key, validate: :string, required: true
  config :domain, validate: :string, required: true
  config :history_filepath,
         validate: :string, default: '/tmp/previous_cf_rayid', required: false
  config :poll_time, validate: :number, default: 15, required: false
  config :default_age, validate: :number, default: 1200, required: false

  public

  def register
    @host = Socket.gethostname
  end # def register

  def read_previous_ray_id
    # read the ray_id of the message which was parsed last
    unless File.exist?(@history_filepath)
      @logger.info("file #{@history_filepath} doesn't exist")
      return ''
    end
    ray_id = File.read(@history_filepath).strip
    ray_id
  end # def read_previous_ray_id

  def write_ray_id(ray_id)
    return nil unless ray_id
    File.open(@history_filepath, 'w') do |file|
      file.write(ray_id)
    end
  end

  def cloudflare_api_call(endpoint, params, multi_line = false)
    url = "https://api.cloudflare.com/client/v4#{endpoint}"
    uri = URI(url)
    uri.query = URI.encode_www_form(params)
    @logger.info('Sending request to Cloudflare')
    Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Get.new(uri.request_uri, 'Accept-Encoding' => 'gzip')
      request['X-Auth-Email'] = @auth_email
      request['X-Auth-Key'] = @auth_key
      response = http.request(request)
      if response.header['Content-Encoding'].eql?('gzip')
        sio = StringIO.new(response.body)
        gz = Zlib::GzipReader.new(sio)
        content = gz.read
      else
        content = response.body
      end
      if response.code != '200'
        raise CloudflareAPIError.new(url, response, content),
              'Error calling Cloudflare API'
      end
      content = content.strip
      lines = []
      return lines if content.empty?
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
  end

  def cloudflare_data(zone_id, ray_id)
    params = {}
    if ray_id && ! ray_id.empty?
      @logger.info("Previous ray_id detected: #{ray_id}")
      params['start_id'] = ray_id
      params['count'] = 100
    else
      @logger.info('Previous ray_id NOT detected')
      params['start'] = Time.now.to_i - @default_age
      params['end'] = params['start'] + 60
    end
    @logger.info("Using params #{params}")
    begin
      entries = cloudflare_api_call("/zones/#{zone_id}/logs/requests",
                                    params, multi_line: true)
    rescue CloudflareAPIError => err
      err.errors.each do |error|
        @logger.error("Cloudflare error code: #{error['code']}: "\
                      "#{error['message']}")
      end
      entries = {}
    end
    if entries.empty?
      @logger.info('No entries returned from Cloudflare')
      return []
    end
    entries
  end # def cloudflare_data

  def fill_cloudflare_data(event, data)
    event['testing'] = data[0]
  end # def fill_cloudflare_data

  def run(queue)
    @logger.info('Starting cloudflare run')
    zone_id = cloudflare_zone_id(@domain)
    @logger.info("Resolved zone ID #{zone_id} for domain #{@domain}")
    until stop?
      begin
        ray_id = read_previous_ray_id
        entries = cloudflare_data(zone_id, ray_id)
        new_ray_id = nil
        @logger.info("Received #{entries.length} events")
        entries.each do |entry|
          event = LogStash::Event.new('host' => @host)
          fill_cloudflare_data(event, entry)
          decorate(event)
          queue << event
          new_ray_id = entry['rayId']
        end
        write_ray_id(new_ray_id)
        @logger.info("Waiting #{@poll_time} seconds before requesting data"\
                     'from Cloudflare again')
        (@poll_time * 2).times do
          sleep(0.5)
        end
      rescue => exception
        break if stop?
        raise(exception)
      end
    end # while loop
  end # def run
end # class LogStash::Inputs::Cloudflare
