# frozen_string_literal: true

# `Syncable#sync_broadcaster` resolves this via `self.class::SyncCompleteEvent`.
class KiteItem::SyncCompleteEvent
  attr_reader :kite_item

  def initialize(kite_item)
    @kite_item = kite_item
  end

  def broadcast
    # Update UI with latest account data
    kite_item.accounts.each do |account|
      account.broadcast_sync_complete
    end

    # Let family handle sync notifications
    kite_item.family.broadcast_sync_complete
  end
end
