require "test_helper"

class Portfolio::ConsoleTradebookTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(
      name: "Console import",
      balance: 0,
      currency: "INR",
      accountable: Investment.new,
      status: "active"
    )
    @security = Security.create!(
      ticker: "INFY#{SecureRandom.hex(3)}",
      name: "Infosys",
      isin: "INE#{SecureRandom.hex(6).upcase}",
      country_code: "IN"
    )
  end

  test "imports buys and sells into the account" do
    result = import(csv: csv([
      row(type: "buy", qty: 10, price: 1500, date: "2026-04-10", trade_id: "T1"),
      row(type: "sell", qty: 4, price: 1700, date: "2026-05-12", trade_id: "T2")
    ]))

    assert result.ok?
    assert_equal 2, result.imported_count

    entries = @account.entries.order(:date)
    assert_equal 2, entries.count
    assert_equal [ 10, -4 ], entries.map { |entry| entry.entryable.qty.to_i }
    assert_equal [ 15_000, -6_800 ], entries.map { |entry| entry.amount.to_i }
    assert_equal Date.new(2026, 4, 10), entries.first.date
  end

  test "is idempotent when the same file is imported twice" do
    rows = [ row(type: "buy", qty: 10, price: 1500, date: "2026-04-10", trade_id: "T1") ]
    import(csv: csv(rows))

    second = import(csv: csv(rows))

    assert_equal 0, second.imported_count
    assert_equal 1, second.skipped
    assert_equal 1, @account.entries.count
  end

  test "a dry run reports without writing" do
    result = import(csv: csv([ row(type: "buy", qty: 10, price: 1500, date: "2026-04-10", trade_id: "T1") ]), dry_run: true)

    assert_equal 1, result.imported_count
    assert_equal 0, @account.entries.count
  end

  test "reports symbols it cannot resolve rather than inventing a security" do
    result = import(csv: "symbol,isin,trade_date,trade_type,quantity,price,trade_id\nNOPE,NOPE123,2026-04-10,buy,1,100,T9")

    assert_equal 0, result.imported_count
    assert_equal [ "NOPE" ], result.unresolved
    assert result.ok?
  end

  test "rejects a CSV without the required columns" do
    result = import(csv: "symbol,isin,trade_date,trade_type,quantity\nX,Y,2026-04-10,buy,1")

    assert_not result.ok?
    assert_match(/missing columns/, result.errors.first)
  end

  test "a bad row fails on its own without stopping the good ones" do
    result = import(csv: csv([
      row(type: "buy", qty: 10, price: 1500, date: "2026-04-10", trade_id: "T1"),
      row(type: "buy", qty: 1, price: 100, date: "not-a-date", trade_id: "T2")
    ]))

    assert_equal 1, result.imported_count
    assert_equal 1, result.errors.size
    assert_match(/line 3/, result.errors.first)
  end

  private
    def import(csv:, dry_run: false)
      Portfolio::ConsoleTradebook.new(family: @family, account: @account, csv: csv, dry_run: dry_run).call
    end

    def csv(rows)
      "symbol,isin,trade_date,trade_type,quantity,price,trade_id\n" + rows.join("\n")
    end

    def row(type:, qty:, price:, date:, trade_id:)
      [ @security.ticker, @security.isin, date, type, qty, price, trade_id ].join(",")
    end
end
