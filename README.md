# Logstash Input Plugin for Cloudflare

[![Circle CI](https://circleci.com/gh/iserko/logstash-input-cloudflare/tree/master.svg?style=svg&circle-token=78044d92053ebb2ad4ca3b45cdf3cbd271d71ac1)](https://circleci.com/gh/iserko/logstash-input-cloudflare/tree/master)

This is a plugin for [Logstash](https://github.com/elastic/logstash).

## Running in isolation (for testing)

```
export CF_AUTH_EMAIL=<email>
export CF_AUTH_KEY=<api_key>
export CF_DOMAIN=<domain>
make
```

Logstash will run in verbose mode, so you will see some messages coming through. In order to verify you're getting results you can open up your browser to http://&lt;IP&gt;:5601 and check Kibana.
Value for the IP address is whatever `docker-machine ip default` says.
