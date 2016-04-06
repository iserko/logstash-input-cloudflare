input {
    cloudflare {
        auth_email => "CF_AUTH_EMAIL"
        auth_key => "CF_AUTH_KEY"
        domain => "CF_DOMAIN"
        type => "cloudflare_logs"
        cf_rayid_filepath => "/logstash-input-cloudflare/previous_cf_rayid"
        cf_tstamp_filepath => "/logstash-input-cloudflare/previous_cf_tstamp"
        fields => [
          'timestamp', 'zoneId', 'ownerId', 'zoneName', 'rayId', 'securityLevel',
          'client.ip', 'client.country', 'client.sslProtocol', 'client.sslCipher',
          'client.deviceType', 'client.asNum', 'clientRequest.bytes',
          'clientRequest.httpHost', 'clientRequest.httpMethod', 'clientRequest.uri',
          'clientRequest.httpProtocol', 'clientRequest.userAgent',
          'edgeResponse.status', 'edgeResponse.bytes'
        ]
    }
}
output {
    elasticsearch {
        hosts => ["esserver:9200"]
        index => "logstash-%{+YYYY.MM.dd}"
    }
}
filter {
 ruby {
   code => "event['timestamp'] /= 1_000_000"
 }
 date {
   match => [ "timestamp", "UNIX_MS" ]
 }
}
