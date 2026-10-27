# The money-weighted return (XIRR) of an investment portfolio: one annual rate
# that reconciles the money the owner put in with what the portfolio is worth
# today.
#
# This is the caller that Portfolio::Xirr's header says is "a later PR". Xirr
# answers "what rate solves this series"; this class decides what the series IS,
# which is the part that can be wrong in a way no arithmetic catches.
#
# TWO BASES, because the two input sets are not interchangeable:
#
#   :external  The exact answer. Cash movements between the owner and the
#              portfolio -- a contribution, a withdrawal -- come from
#              Portfolio::FlowClassifier, which is the one place that decides
#              what those are. Needs contribution/withdrawal entries to exist.
#
#   :trades    The approximation, for portfolios that were anchored from
#              holdings and therefore have no contribution history at all.
#              Every buy is treated as money arriving on the day it was bought
#              and every sell as money leaving on the day it was sold.
#
# :trades is exact only when no cash ever sat idle in the account between a
# deposit and a purchase. When it did, the deposit's real date is earlier than
# the buy it funded, and the rate this produces is slightly flattering. That is
# a stated assumption rather than a bug, and it is why #basis is public and the
# view says which one produced the figure.
#
# What is NOT a flow, on either basis: dividends and interest (they are income
# already earned inside the portfolio, not money the owner injected), fees (the
# money stayed in the account, it just bought less), and internal movements
# (a position moved between two accounts you own realises nothing). The
# vocabulary for all three is taken from Portfolio::FlowClassifier and Trade
# rather than restated here, so adding a label there cannot quietly change this
# class's answer.
#
# The closing value is appended as the final positive flow, because the owner
# has not sold -- the portfolio is worth that today and XIRR needs a terminal
# return of capital to have anything to solve.
class Portfolio::MoneyWeightedReturn
  BASISES = %i[trades external].freeze

  attr_reader :account_ids, :currency, :closing_value, :as_of, :basis

  # `account_ids` must already be scoped to accounts the caller is allowed to
  # see; like Portfolio::FlowClassifier this class does not re-filter by family.
  #
  # `closing_value` is the portfolio's value in `currency` on `as_of`. A nil or
  # zero closing value means the series has no terminal flow and #rate is nil:
  # a portfolio worth nothing today has no rate, and reporting the rate of the
  # flows alone would answer a different question.
  def initialize(account_ids:, currency:, closing_value:, as_of: Date.current, basis: :trades)
    @account_ids = Array(account_ids).map(&:to_s).uniq.freeze
    @currency = currency.to_s
    @closing_value = closing_value.to_d
    @as_of = as_of.to_date
    @basis = basis.to_sym

    raise ArgumentError, "unknown basis #{basis.inspect}, expected one of #{BASISES.inspect}" unless BASISES.include?(@basis)
    raise ArgumentError, "currency is required" if @currency.blank?
  end

  # The series handed to Portfolio::Xirr, as [date, amount] pairs. Money leaving
  # the owner is negative; money coming back to them is positive.
  def flows
    @flows ||= (cash_flows + terminal_flows).sort_by { |date, _| date }.freeze
  end

  # BigDecimal (0.0725 == 7.25%), or nil when no rate exists. Nil is a real
  # answer here -- money only ever went one way, every flow fell on one date, or
  # the solver did not converge -- and the view must render it as "not
  # available" rather than substituting a guess.
  def rate
    return @rate if defined?(@rate)

    @rate = Portfolio::Xirr.rate_or_nil(flows)
  end

  def available?
    !rate.nil?
  end

  # True when the series MAY have more than one rate. Callers should hedge the
  # figure rather than print it as "the" return; see Portfolio::Xirr.
  def ambiguous?
    @ambiguous = Portfolio::Xirr.new(flows).ambiguous? unless defined?(@ambiguous)
    @ambiguous
  end

  def first_flow_on
    flows.first&.first
  end

  private
    def terminal_flows
      return [] unless closing_value.positive?

      [ [ as_of, closing_value ] ]
    end

    def cash_flows
      basis == :external ? external_cash_flows : trade_cash_flows
    end

    # One query for the whole series. FX is joined on the entry's own date, the
    # same way InvestmentStatement::Totals does it, so a EUR trade in a USD
    # portfolio is converted at the rate for the day it happened rather than
    # today's. COALESCE(er.rate, 1) matches that reader's existing fallback
    # rather than introducing a second, stricter policy inside one statement.
    def trade_cash_flows
      rows = ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([
          <<~SQL.squish,
            SELECT entries.date AS entry_date,
                   trades.qty AS qty,
                   trades.investment_activity_label AS label,
                   entries.amount * COALESCE(er.rate, 1) AS amount
            FROM entries
            INNER JOIN trades ON trades.id = entries.entryable_id AND entries.entryable_type = 'Trade'
            LEFT JOIN exchange_rates er ON (
              er.date = entries.date
              AND er.from_currency = entries.currency
              AND er.to_currency = :currency
            )
            WHERE entries.account_id IN (:account_ids)
              AND entries.date <= :as_of
              AND entries.excluded IS NOT TRUE
          SQL
          { currency: currency, account_ids: account_ids, as_of: as_of }
        ])
      ).to_a

      rows.filter_map do |row|
        qty = row["qty"].to_d
        label = row["label"]

        next if qty.zero?
        next if Trade::INTERNAL_MOVEMENT_LABELS.include?(label)
        next if Portfolio::FlowClassifier::INCOME_LABELS.include?(label)
        next if Portfolio::FlowClassifier::FEE_LABELS.include?(label)

        # entries.amount is signed by the trade direction in every storage shape
        # the classifier documents, but the sign is re-derived from qty so a
        # provider that writes a positive amount for a sell cannot flip a flow.
        [ row["entry_date"].to_date, row["amount"].to_d.abs * (qty.positive? ? -1 : 1) ]
      end
    end

    def external_cash_flows
      rows = ActiveRecord::Base.connection.select_all(
        ActiveRecord::Base.sanitize_sql_array([
          <<~SQL.squish,
            SELECT entries.id AS entry_id,
                   entries.date AS entry_date,
                   entries.amount * COALESCE(er.rate, 1) AS amount
            FROM entries
            LEFT JOIN exchange_rates er ON (
              er.date = entries.date
              AND er.from_currency = entries.currency
              AND er.to_currency = :currency
            )
            WHERE entries.account_id IN (:account_ids)
              AND entries.date <= :as_of
              AND entries.excluded IS NOT TRUE
          SQL
          { currency: currency, account_ids: account_ids, as_of: as_of }
        ])
      ).to_a
      return [] if rows.empty?

      classes = Portfolio::FlowClassifier
        .new(scope_account_ids: account_ids)
        .classify_ids(rows.map { |row| row["entry_id"] })

      rows.filter_map do |row|
        case classes[row["entry_id"]]
        when :external_inflow then [ row["entry_date"].to_date, -row["amount"].to_d.abs ]
        when :external_outflow then [ row["entry_date"].to_date, row["amount"].to_d.abs ]
        end
      end
    end
end
