require "sidekiq"
require "sidekiq/api"
require "active_support"
require "active_support/core_ext"

require "sidekiq/statsd/version"
require "sidekiq/statsd/server_middleware"
require "sidekiq/metrics/carbon/server_middleware"
require "sidekiq/metrics/graphite/server_middleware"
