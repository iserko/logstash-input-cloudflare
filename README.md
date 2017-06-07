# Logstash Input Plugin for Cloudflare

[![Circle CI](https://circleci.com/gh/iserko/logstash-input-cloudflare/tree/master.svg?style=svg&circle-token=78044d92053ebb2ad4ca3b45cdf3cbd271d71ac1)](https://circleci.com/gh/iserko/logstash-input-cloudflare/tree/master)

This is a plugin for [Logstash](https://github.com/elastic/logstash) and it allows Logstash to read web request logs from the Cloudflare ELS API. Then Logstash can parse those logs and store them into your store (ElasticSearch if you use the ELK stack).

The repository provides a sample logstash configuration which you can use and should just work (as long as you fill in `CF_AUTH_EMAIL`, `CF_AUTH_KEY` and `CF_DOMAIN`). Take the (example config file](https://github.com/iserko/logstash-input-cloudflare/blob/master/logstash.conf.m4) 

Read https://support.cloudflare.com/hc/en-us/articles/216672448-Enterprise-Log-Share-REST-API for more information about the Cloudflare Enterprise Log Share feature. **You are required to be a Cloudflare's Enterprise customer in order to use this plugin**

## Configuration

```
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
          'edgeResponse.status', 'edgeResponse.bytes', 'edgeResponse.bodyBytes',
          'originResponse.status', 'origin.responseTime'
        ]
    }
}
```

Setting | Description | Default Value | Required
------- | ----------- | ------------- | --------
auth_email | Email used to login to Cloudflare (suggest creating a new user with only the permissions to access the ELS API | - | true
auth_key | API key user to login to Cloudflare | - | true
domain | The domain you watch to read logs for (since Cloudflare works on top level domains, that usually means something like `example.com`) | - | true
poll_time | The time in seconds between different API calls | 15 | false
poll_interval | The time in seconds which determines how many web request logs we pull down from the API (only used when there is no state) | 60 | false
start_from_secs_ago | The time in seconds which determines how far back in the past you want to start processing logs from | 1200 | false
batch_size | Number of events per API call to get. Helps reduce memory overhead | 1000 | false
fields | List of fields you want to process from the API (read the [ELS schema](https://support.cloudflare.com/hc/en-us/article_attachments/205413947/els_schema.json)) | See [fields](https://github.com/iserko/logstash-input-cloudflare/blob/master/lib/logstash/inputs/cloudflare.rb#L54-L60) | false

## Running in isolation (for testing)

**You need to be running Docker locally in order to use this!**

```
export CF_AUTH_EMAIL=<email>
export CF_AUTH_KEY=<api_key>
export CF_DOMAIN=<domain>
make
```

Logstash will run in verbose mode, so you will see some messages coming through. In order to verify you're getting results you can open up your browser to http://&lt;IP&gt;:5601 and check Kibana.
Value for the IP address is whatever `docker-machine ip default` says or if you use Docker For Mac ... it's just 127.0.0.1.
