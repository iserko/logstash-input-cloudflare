input {
    cloudflare {
        auth_email => "CF_AUTH_EMAIL"
        auth_key => "CF_AUTH_KEY"
        domain => "CF_DOMAIN"
        type => "cloudflare_logs"
        history_filepath => "/logstash-input-cloudflare/previous_cf_rayid"
    }
}
output {
    elasticsearch {
        hosts => ["esserver:9200"]
        index => "cloudflare-logstash-%{+YYYY.MM.dd}"
    }
}
filter {
}
