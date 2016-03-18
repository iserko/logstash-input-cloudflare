# Logstash Input Plugin for Cloudflare

This is a plugin for [Logstash](https://github.com/elastic/logstash).

## Running in isolation (for testing)

```
export CF_AUTH_EMAIL=<email>
export CF_AUTH_KEY=<api_key>
export CF_DOMAIN=<domain>
make
```

Logstash will run in verbose mode, so you will see some messages coming through. In order to verify you're getting results you can open up your browser to http://<IP>:5601 and check Kibana.
Value for the IP address is whatever `docker-machine ip default` says.
