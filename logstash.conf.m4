input {
    cloudflare {
        auth_email => "CF_AUTH_EMAIL"
        auth_key => "CF_AUTH_KEY"
        domain => "CF_DOMAIN"
        type => "cloudflare_logs"
        cf_rayid_filepath => "/logstash-input-cloudflare/previous_cf_rayid"
        cf_tstamp_filepath => "/logstash-input-cloudflare/previous_cf_tstamp"
    }
}
output {
    elasticsearch {
        hosts => ["esserver:9200"]
        index => "logstash-%{+YYYY.MM.dd}"
    }
}
filter {
}
