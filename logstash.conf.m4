input {
    cloudflare {
        auth_email => "CF_AUTH_EMAIL"
        auth_key => "CF_AUTH_KEY"
        domain => "CF_DOMAIN"
        type => "cloudflare_logs"
        poll_time => 15
        poll_interval => 120
        metadata_filepath => "/logstash-input-cloudflare/cf_metadata.json"
        fields => [
          'timestamp', 'zoneId', 'ownerId', 'zoneName', 'rayId', 'securityLevel',
          'client.ip', 'client.country', 'client.sslProtocol', 'client.sslCipher',
          'client.deviceType', 'client.asNum', 'clientRequest.bytes',
          'clientRequest.httpHost', 'clientRequest.httpMethod', 'clientRequest.uri',
          'clientRequest.httpProtocol', 'clientRequest.userAgent', 'cache.cacheStatus',
          'edge.cacheResponseTime', 'edge.startTimestamp', 'edge.endTimestamp',
          'edgeResponse.status', 'edgeResponse.bytes', 'originResponse.status',
          'origin.responseTime'
        ]
    }
}
output {
    elasticsearch {
        hosts => ["esserver:9200"]
        index => "logstash-%{+YYYY.MM.dd}"
        template_name => "cloudflare-logstash"
        doc_as_upsert => true
        document_id => "%{rayId}"
        template_overwrite => true
    }
}
filter {
 ruby {
   code => "event['timestamp_ms'] /= 1_000_000"
 }
 ruby {
   code => "event['edge_requestTime'] = (event['edge_endTimestamp'] - event['edge_startTimestamp']).to_f / 1_000_000_000"
 }
 ruby {
   code => "event['edgeResponse_headerBytes'] = event['edgeResponse_bytes'].to_i - event['edgeResponse_bodyBytes'].to_i"
 }
 date {
   match => [ "timestamp_ms", "UNIX_MS" ]
 }
 geoip {
   source => "client_ip"
 }
 useragent {
   source => "clientRequest.userAgent"
 }
}
