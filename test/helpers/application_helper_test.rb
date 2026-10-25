require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  # format_money reads Current.family, so every test here must leave the
  # thread-local session the way it found it.
  setup { @original_session = Current.session }

  teardown { Current.session = @original_session }

  test "#icon normalizes icon names to lowercase" do
    capture = []

    singleton_class.send(:define_method, :lucide_icon) do |key, **opts|
      capture << [ key, opts ]
      "<svg></svg>".html_safe
    end

    icon("Key")

    assert_equal "key", capture.first.first
  ensure
    singleton_class.send(:remove_method, :lucide_icon) if singleton_class.method_defined?(:lucide_icon)
  end

  test "#icon falls back when lucide icon is unknown" do
    calls = []

    singleton_class.send(:define_method, :lucide_icon) do |key, **_opts|
      calls << key
      raise ArgumentError, "Unknown icon #{key}" if key == "not-a-real-icon"

      "<svg></svg>".html_safe
    end

    result = icon("not-a-real-icon")

    assert_equal [ "not-a-real-icon", "key" ], calls
    assert_equal "<svg></svg>", result
  ensure
    singleton_class.send(:remove_method, :lucide_icon) if singleton_class.method_defined?(:lucide_icon)
  end

  test "#title(page_title)" do
    title("Test Title")
    assert_equal "Test Title", content_for(:title)
  end

  test "#header_title(page_title)" do
    header_title("Test Header Title")
    assert_equal "Test Header Title", content_for(:header_title)
  end

  test "#sidekiq_web_available? returns true when the route is mounted" do
    named_routes = Struct.new(:defined) do
      def route_defined?(name)
        defined.fetch(name)
      end
    end

    Rails.application.routes.stub(:named_routes, named_routes.new({ sidekiq_web_path: true })) do
      assert sidekiq_web_available?
    end
  end

  test "#sidekiq_web_available? returns false when the route is unavailable" do
    named_routes = Struct.new(:defined) do
      def route_defined?(name)
        defined.fetch(name, false)
      end
    end

    Rails.application.routes.stub(:named_routes, named_routes.new({})) do
      assert_not sidekiq_web_available?
    end
  end

  test "#sidekiq_web_available? returns true when only the url helper is defined" do
    named_routes = Struct.new(:defined) do
      def route_defined?(name)
        defined.fetch(name, false)
      end
    end

    Rails.application.routes.stub(:named_routes, named_routes.new({ sidekiq_web_url: true })) do
      assert sidekiq_web_available?
    end
  end

  def setup
    @account1 = Account.new(currency: "USD", balance: 1)
    @account2 = Account.new(currency: "USD", balance: 2)
    @account3 = Account.new(currency: "EUR", balance: -7)
  end

  test "#styled_form_with keeps a field's help_text when the field has no label" do
    html = styled_form_with(url: "/", scope: :account) do |form|
      form.text_field :name, label: false, help_text: "Shown to everyone in the family"
    end

    fragment = Nokogiri::HTML.fragment(html)
    assert_equal "Shown to everyone in the family", fragment.at("p#account_name_help_text")&.text
    assert_equal "account_name_help_text", fragment.at("input[name='account[name]']")["aria-describedby"]
  end

  test "#totals_by_currency(collection: collection, money_method: money_method)" do
    assert_equal "$3.00", totals_by_currency(collection: [ @account1, @account2 ], money_method: :balance_money)
    assert_equal "$3.00 | -€7.00", totals_by_currency(collection: [ @account1, @account2, @account3 ], money_method: :balance_money)
    assert_equal "", totals_by_currency(collection: [], money_method: :balance_money)
    assert_equal "$0.00", totals_by_currency(collection: [ Account.new(currency: "USD", balance: 0) ], money_method: :balance_money)
    assert_equal "-$3.00 | €7.00", totals_by_currency(collection: [ @account1, @account2, @account3 ], money_method: :balance_money, negate: true)
  end

  test "#currency_picker_options_for_family returns enabled family currencies" do
    family = families(:dylan_family)
    family.update!(currency: "SGD", enabled_currencies: [ "USD" ])

    assert_equal [ "SGD", "USD" ], currency_picker_options_for_family(family)
  end

  test "#currency_picker_options_for_family keeps selected legacy currency visible" do
    family = families(:dylan_family)
    family.update!(currency: "SGD", enabled_currencies: [ "USD" ])

    assert_equal [ "SGD", "USD", "EUR" ], currency_picker_options_for_family(family, extra: "EUR")
  end

  # --- Digit grouping follows the family's number_format preference. ---
  # format_money is the single display path for money in the app, so the
  # preference is wired in here rather than at every call site.

  test "#format_money groups in thousands for a western family" do
    use_family(number_format: "western")

    assert_equal "$1,234,567.00", format_money(Money.new(1_234_567, :usd))
  end

  test "#format_money groups in lakhs and crores for an Indian family" do
    use_family(number_format: "lakh_crore")

    assert_equal "$12,34,567.00", format_money(Money.new(1_234_567, :usd))
  end

  test "#format_money reads one crore as 1,00,00,000" do
    use_family(number_format: "lakh_crore")

    assert_equal "$1,00,00,000", format_money(Money.new(10_000_000, :usd), precision: 0)
  end

  # precision: and format: must survive the grouping change, which is why the
  # pattern rides through Money#format instead of bypassing it.
  test "#format_money keeps precision and the locale's own delimiter style" do
    use_family(number_format: "lakh_crore")

    assert_equal "$12,34,567", format_money(Money.new(1_234_567.4, :usd), precision: 0)
    # Polish groups with a space, so the Indian pattern inserts a space too —
    # the grouping is lakh/crore, the separator stays what that locale uses.
    assert_equal "12 34 567,00 zł", format_money(Money.new(1_234_567, :pln), locale: :pl)
  end

  test "#format_money keeps a negative sign and leaves ungrouped amounts alone" do
    use_family(number_format: "lakh_crore")

    assert_equal "-$12,34,567.00", format_money(Money.new(-1_234_567, :usd))
    assert_equal "$1,000.00", format_money(Money.new(1000, :usd))
    assert_equal "$99.00", format_money(Money.new(99, :usd))
  end

  test "#format_money returns nil for nil under either grouping" do
    use_family(number_format: "lakh_crore")

    assert_nil format_money(nil)
  end

  private

    def use_family(number_format:)
      family = families(:dylan_family)
      family.update!(number_format: number_format)
      Current.session = family.users.first.sessions.create!
    end
end
