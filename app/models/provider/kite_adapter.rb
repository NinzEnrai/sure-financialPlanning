class Provider::KiteAdapter < Provider::Base
  include Provider::Syncable
  include Provider::InstitutionMetadata

  # Register this adapter with the factory. Without this the dashboard raises
  # AdapterNotFoundError on any account linked to a KiteAccount, because
  # Account#logo_url asks the factory for an adapter by provider_type (the class
  # name, "KiteAccount").
  Provider::Factory.register("KiteAccount", self)

  # Zerodha is a broker, not a bank: investment accounts only.
  def self.supported_account_types
    %w[Investment]
  end

  # Kite is not a family-connectable provider in the same sense as SnapTrade:
  # its credentials come from the environment, so there is nothing for a family
  # to supply and no new-account path to hand out.
  def self.connection_configs(family:)
    []
  end

  def provider_name
    "kite"
  end

  def item
    provider_account.kite_item
  end

  def sync_path
    return nil unless item

    Rails.application.routes.url_helpers.connect_settings_kite_connection_path
  end

  # Zerodha reports a live holdings snapshot rather than a ledger of transfers,
  # so holdings must not be deleted when a connection is removed -- doing so
  # would destroy the family's portfolio history.
  def can_delete_holdings?
    false
  end

  def institution_domain
    "zerodha.com"
  end

  def institution_name
    item&.name.presence || "Zerodha"
  end

  def institution_url
    "https://zerodha.com"
  end

  def institution_color
    nil
  end
end
