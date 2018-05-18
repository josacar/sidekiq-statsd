# encoding: utf-8

require 'net/http'
require 'uri'

module Sidekiq; module Metrics; module Graphite
  ##
  # Sidekiq StatsD is a middleware to track worker execution metrics through statsd.
  #
  class ServerMiddleware
    # Content-Type: application/vnd.sumologic.graphite
    #
    # prod.lb-1.cpu 87.2 1501753030
    # prod.lb-1.memory 32390 1501753030
    # prod.lb-1.disk 2.2 1501753030
    # prod.lb-1.cpu 84.6 1501753040
    # prod.lb-1.memory 32250 1501753040
    ##
    # Initializes the middleware with options.
    #
    # Compressed data
    # Content-Encoding
    # gzip or deflate
    # Required if you are uploading compressed data.
    #
    # Content Type (for Metrics)
    # Content-Type
    # application/vnd.sumologic.graphite or application/vnd.sumologic.carbon2
    # Required if you are uploading metrics.
    #
    # Custom Source Name
    # X-Sumo-Name
    # Desired source name.
    # Useful if you want to override the source name configured for the source.
    #
    # Custom Source Host
    # X-Sumo-Host
    # Desired host name.
    # Useful if you want to override the source host configured for the source.
    #
    # Custom Source Category
    # X-Sumo-Category
    # Desired source category.
    # Useful if you want to override the source category configured for the source.
    #
    # Custom Metric Dimensions
    # X-Sumo-Dimensions
    # Comma-separated key=value list of dimensions to apply to every metric.
    # For metrics only. Custom dimensions will allow you to query your metrics at a more granular level.
    #
    # Custom Metric Metadata
    # X-Sumo-Metadata
    # Comma-separated, key=value list of metadata to apply to every metric.
    # For metrics only. Custom metadata  will allow you to query your metrics at a more granular level

    # @param [Hash] options The options to initialize the Graphite client.
    # @option options [Statsd] :statsd Existing statsd client.
    # @option options [String] :env ("production") The env to segment the metric key (e.g. env.prefix.worker_name.success|failure).
    # @option options [String] :prefix ("worker") The prefix to segment the metric key (e.g. env.prefix.worker_name.success|failure).
    # @option options [String] :uri ("localhost") Sumologic endpoint
    # @option options [String] :sidekiq_stats ("true") Send Sidekiq global stats e.g. total enqueued, processed and failed.
    def initialize(options = {})
      default_options = {
        env: 'production',
        prefix: 'worker',
        uri: 'localhost',
        sidekiq_stats:  true
      }

      @options = default_options.merge(options)
      @sidekiq_stats = Sidekiq::Stats.new if @options[:sidekiq_stats]
    end

    ##
    # Pushes the metrics in a batch.
    #
    # @param worker [Sidekiq::Worker] The worker the job belongs to.
    # @param msg [Hash] The job message.
    # @param queue [String] The current queue.
    def call(worker, msg, queue)
      batch = []

      begin
        worker_name = worker.class.name.gsub('::', '.')

        start = Time.now
        yield
        duration = ((Time.now - start) * 1000).round(5)

        batch.append metric(prefix(worker_name, 'processing_time'), duration)
        # b.increment prefix(worker_name, 'success')
      rescue => e
        # b.increment prefix(worker_name, 'failure')
        raise e
      ensure
        if @options[:sidekiq_stats]
          # Queue sizes
          batch.append metric(prefix('enqueued'), @sidekiq_stats.enqueued)
          if @sidekiq_stats.respond_to?(:retry_size)
            # 2.6.0 doesn't have `retry_size`
            batch.append metric(prefix('retry_set_size'), @sidekiq_stats.retry_size)
          end

          # All-time counts
          batch.append metric(prefix('processed'), @sidekiq_stats.processed)
          batch.append metric(prefix('failed'), @sidekiq_stats.failed)
        end

        # Queue metrics
        queue_name = msg['queue']
        sidekiq_queue = Sidekiq::Queue.new(queue_name)
        batch.append metric(prefix('queues', queue_name, 'enqueued'), sidekiq_queue.size)
        if sidekiq_queue.respond_to?(:latency)
          batch.append metric(prefix('queues', queue_name, 'latency'), sidekiq_queue.latency)
        end
      end

      headers = { 'Content-Type': 'application/vnd.sumologic.graphite' }
      post_data = batch.join("\n")

      uri = URI.parse(@options[:uri])

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri.request_uri, headers)
      request.body = post_data

      http.request(request)
    end

    private

    ##
    # Converts args passed to it into a metric name with prefix.
    #
    # @param [String] args One or more strings to be converted to a metric name.
    def prefix(*args)
      [@options[:env], @options[:prefix], *args].compact.join('.')
    end

    def metric(metric_name, value)
      @timestamp ||= Time.now.utc.to_i
      "#{metric_name} #{value} #{@timestamp}"
    end
  end
end; end; end
