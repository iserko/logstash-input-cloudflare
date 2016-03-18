CF_AUTH_EMAIL := $(shell echo $${CF_AUTH_EMAIL})
CF_AUTH_KEY := $(shell echo $${CF_AUTH_KEY})
CF_DOMAIN := $(shell echo $${CF_DOMAIN})

default: logstash.conf
	docker-compose up -d kibana
	docker-compose run logstash

logstash.conf:
	@m4 -D CF_AUTH_EMAIL=${CF_AUTH_EMAIL} -D CF_AUTH_KEY=${CF_AUTH_KEY} \
		-D CF_DOMAIN=${CF_DOMAIN} logstash.conf.m4 > logstash.conf
