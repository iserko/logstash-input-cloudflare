## 0.9.11
- added option to set open and read timeouts for API calls.

## 0.9.10
- fixed an issue when Cloudflare wouldn't return a value for a field, Elasticsearch would return
  an error and fail to process the message. Error in question was:
  ```
  {"type"=>"illegal_state_exception", "reason"=>"Can't get text on a END_OBJECT at 1:718"}
  ```

## 0.9.9
- changed default location of metadata_filepath file to /var/lib instead of /tmp

## 0.9.8
- fix for domain names not found with large accounts

## 0.9.7
- bugfix from leftover refactor

## 0.9.6
- using rubocop to keep the code tidy
- cleaned up code in order to make rubocop happy
- worker will now catch-up if it was shut off for some time

## 0.9.5
- moar bugfixes

## 0.9.4
- bugfix release to fix a bug in 0.9.3

## 0.9.3
- CloudFlare API now works with start_id & count \o/

## 0.9.2
- fixing situations when you have no visits and the API would be constantly requested
- fixed address in gemspec

## 0.9.1
- first working version of plugin

## 0.1.0
- Initial version of the Cloudflare input plugin
