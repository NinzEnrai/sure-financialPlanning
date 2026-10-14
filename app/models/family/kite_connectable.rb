module Family::KiteConnectable
  extend ActiveSupport::Concern

  included do
    # One Zerodha login per family. The unique index on kite_items.family_id
    # enforces that at the database level, so has_one is the honest shape here --
    # a has_many would let a second connection through the model and only fail
    # on insert.
    has_one :kite_item, dependent: :destroy
  end

  def can_connect_kite?
    # Credentials are entered by the family (their own Kite Connect app), so no
    # environment-level app configuration gates this the way SnapTrade's
    # env-level OAuth does.
    true
  end
end
