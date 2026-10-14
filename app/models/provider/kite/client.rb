# frozen_string_literal: true

require "net/http"
require "json"
require "digest"

class Provider
  module Kite
    # Low-level HTTP wrapper for the Kite Connect v3 REST API.
    # Every other Kite service object should go through this class so that rate limiting,
    # backoff, auth headers, and error normalization live in exactly one place.
    #
    # Kite enforces roughly 3 req/sec per API key on most endpoints (tighter on order
    # endpoints, which we don't use here since this is a read-only portfolio/MF sync).
    # We self-throttle *below* that limit rather than relying solely on reacting to 429s,
    # since Zerodha's own docs warn that repeated limit breaches can trigger temporary bans.
    class Client
      BASE_URL = "https://api.kite.trade"
      MAX_REQUESTS_PER_SECOND = 2 # stay comfortably under Kite's ~3/sec cap
      MAX_RETRIES = 5
      BASE_BACKOFF_SECONDS = 1.0

      class RateLimitExceeded < StandardError; end
      class AuthenticationExpired < StandardError; end
      class KiteApiError < StandardError
        attr_reader :status, :body
        def initialize(message, status: nil, body: nil)
          super(message)
          @status = status
          @body = body
        end
      end

      def initialize(kite_item)
        @connection = kite_item
      end

      def get(path, params = {})
        request(:get, path, params: params)
      end

      def post(path, form_data = {})
        request(:post, path, form_data: form_data)
      end

      private

        attr_reader :connection

        def request(method, path, params: {}, form_data: {})
          throttle!

          attempt = 0
          begin
            attempt += 1
            response = perform_http(method, path, params, form_data)
            handle_response(response)
          rescue RateLimitExceeded, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
            raise e if attempt >= MAX_RETRIES

            sleep_for = backoff_seconds(attempt, response: defined?(response) ? response : nil)
            Rails.logger.warn("[Kite] retrying #{method.upcase} #{path} (attempt #{attempt}) after #{sleep_for.round(1)}s: #{e.class}")
            sleep(sleep_for)
            retry
          end
        end

        def perform_http(method, path, params, form_data)
          uri = URI.join(BASE_URL, path)
          uri.query = URI.encode_www_form(params) if params.present?

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = 5
          http.read_timeout = 10

          req =
            case method
            when :get  then Net::HTTP::Get.new(uri)
            when :post then Net::HTTP::Post.new(uri).tap { |r| r.set_form_data(form_data) }
            else raise ArgumentError, "unsupported method #{method}"
            end

          req["X-Kite-Version"] = "3"
          req["Authorization"] = "token #{connection.api_key}:#{connection.access_token}"

          http.request(req)
        end

        def handle_response(response)
          case response.code.to_i
          when 200
            JSON.parse(response.body)
          when 403
            # Kite returns 403 with error_type "TokenException" for expired/invalid session tokens.
            body = safe_json(response.body)
            if body.dig("error_type") == "TokenException"
              connection.mark_needs_reauth!(reason: body["message"])
              raise AuthenticationExpired, body["message"]
            end
            raise KiteApiError.new(body["message"] || "Forbidden", status: 403, body: body)
          when 429
            raise RateLimitExceeded, "Kite rate limit hit"
          when 500..599
            raise KiteApiError.new("Kite server error #{response.code}", status: response.code.to_i)
          else
            body = safe_json(response.body)
            raise KiteApiError.new(body["message"] || "Kite API error #{response.code}",
                                    status: response.code.to_i, body: body)
          end
        end

        def safe_json(body)
          JSON.parse(body)
        rescue JSON::ParserError
          {}
        end

        def backoff_seconds(attempt, response: nil)
          retry_after = response&.respond_to?(:[]) ? response["Retry-After"]&.to_f : nil
          return retry_after if retry_after

          # Exponential backoff with jitter: base * 2^(attempt-1) +/- 20%
          base = BASE_BACKOFF_SECONDS * (2**(attempt - 1))
          jitter = base * (rand(-0.2..0.2))
          [ base + jitter, 30.0 ].min
        end

        # Simple per-process token bucket. For multi-dyno/multi-worker deployments, swap this
        # for a Redis-backed limiter (e.g. a sliding-window counter keyed on the connection id)
        # since Sure already runs Redis for Sidekiq -- happy to wire that up once I can see how
        # your app currently accesses Redis (Redis.current, a dedicated connection pool, etc).
        def throttle!
          self.class.mutex.synchronize do
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            elapsed = now - self.class.last_request_at
            min_interval = 1.0 / MAX_REQUESTS_PER_SECOND
            sleep(min_interval - elapsed) if elapsed < min_interval
            self.class.last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
        end

        class << self
          attr_accessor :last_request_at

          def mutex
            @mutex ||= Mutex.new
          end
        end

        self.last_request_at = 0
    end
  end
end
