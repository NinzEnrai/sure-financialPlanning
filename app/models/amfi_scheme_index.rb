# frozen_string_literal: true

# Maps a mutual fund ISIN to its AMFI scheme code.
#
# Zerodha's /mf/holdings identifies a fund by ISIN ("INF959L01FX6"), but the
# AMFI NAV feed every fund price comes from is keyed by scheme code ("149892").
# Without this mapping a Kite-imported fund can never be priced: mfapi answers
# 400 for an ISIN, so the security keeps no NAV history and XIRR / tax features
# have nothing to work from.
#
# AMFI publishes both identifiers on the same row, so the official daily NAV
# file is the mapping's source of truth -- no third-party service, no key.
class AmfiSchemeIndex
  SOURCE_URL = ENV.fetch("AMFI_NAV_URL", "https://www.amfiindia.com/spages/NAVAll.txt")
  CACHE_KEY = "amfi_scheme_index_by_isin"
  CACHE_TTL = 1.day

  # ISO 6166: two-letter country prefix, nine alphanumerics, one check digit.
  ISIN_PATTERN = /\A[A-Z]{2}[A-Z0-9]{9}\d\z/
  # A data row starts with the scheme code; section headings and fund-house
  # names look nothing like this, so they drop out.
  DATA_ROW_PATTERN = /\A\d+;/

  class << self
    # Returns the scheme code for an ISIN, or nil when the ISIN is unknown (or
    # the feed is unavailable). Callers must treat nil as "cannot price", never
    # as an error.
    def scheme_code_for(isin)
      isin = normalize(isin)
      return nil unless isin.match?(ISIN_PATTERN)

      index[isin]
    end

    def index
      cached = Rails.cache.read(CACHE_KEY)
      return cached if cached.present?

      fresh = fetch_index
      # Never cache an empty result: AMFI answers 302 (and occasionally 5xx), and
      # caching that would leave every fund unpriced for a whole day.
      Rails.cache.write(CACHE_KEY, fresh, expires_in: CACHE_TTL) if fresh.present?
      fresh
    end

    # Exposed for tests and for a manual refresh after AMFI adds a fund.
    def refresh!
      Rails.cache.delete(CACHE_KEY)
      index
    end

    def isin?(value)
      normalize(value).match?(ISIN_PATTERN)
    end

    # Parses the file body. Split out from the fetch so it can be tested without
    # the network.
    def parse(body)
      body.to_s.each_line.each_with_object({}) do |line, map|
        line = line.strip
        next unless line.match?(DATA_ROW_PATTERN)

        scheme_code, isin_payout, isin_reinvestment = line.split(";", 4)
        next if scheme_code.blank?

        # A fund with two ISINs (payout/IDCW and reinvestment) shares one scheme
        # code; both must resolve, or half the folios would go unpriced.
        [ isin_payout, isin_reinvestment ].each do |isin|
          isin = normalize(isin)
          map[isin] = scheme_code.strip if isin.match?(ISIN_PATTERN)
        end
      end
    end

    private

      def fetch_index
        body = download(SOURCE_URL)

        unless body
          Rails.logger.warn("[AmfiSchemeIndex] AMFI feed unavailable; fund ISIN lookup disabled this cycle")
          return {}
        end

        parsed = parse(body)
        Rails.logger.warn("[AmfiSchemeIndex] AMFI feed parsed to zero ISINs; format may have changed") if parsed.empty?
        parsed
      end

      # AMFI answers the canonical URL with a 302 rather than the file, and plain
      # Faraday does not follow it -- the body is then a 169-byte redirect page
      # that parses to nothing. Follow one hop by hand: no extra middleware, and
      # a loop cannot form.
      def download(url, hops: 1)
        response = Faraday.get(url) do |request|
          request.options.timeout = 20
          request.options.open_timeout = 10
        end

        if response.status.between?(300, 399)
          location = response.headers["location"]
          return nil if location.blank? || hops.zero?

          return download(URI.join(url, location).to_s, hops: hops - 1)
        end

        return nil unless response.success?

        response.body
      rescue StandardError => e
        # A fund that cannot be priced is one missing chart, not a failed sync:
        # degrade to "unknown" rather than raising into the caller.
        Rails.logger.warn("[AmfiSchemeIndex] AMFI feed unavailable: #{e.class} - #{e.message}")
        nil
      end

      def normalize(value)
        value.to_s.strip.upcase
      end
  end
end
