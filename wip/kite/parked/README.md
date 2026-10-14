# Parked Kite code

`KiteItem` does **not** `include Syncable`, so these two files are unused and are
not loaded. They are kept here because they are written and correct-by-shape, and
because a future Kite-adjacent provider (or a move back to `Syncable`-driven
scheduling) would want them.

## Why they were removed

Kite syncs are scheduled by sidekiq-cron via `Kite::SyncScheduler`, not by
`Syncable#sync_later`. The live path is:

```
Kite::SyncPortfolioJob -> KiteItem#import_latest_kite_data -> KiteItem::Importer
                                          |
                                          +-> HoldingsSync / TradeImporter / MutualFundSync
                                          +-> account.sync_later   (the balance materialization)
```

`Syncable#perform_sync` -> `KiteItem::Syncer` and `Syncable#broadcast_sync_complete`
-> `KiteItem::SyncCompleteEvent` were never on that path, so all they did was add
dead constants.

## What removing Syncable actually fixed

`Syncable` defines `last_synced_at` as `latest_completed_sync_record&.completed_at`.
Kite never creates a `Sync`, so that method returned `nil` forever and **shadowed
the `last_synced_at` column**. `KiteItem#record_sync!` was writing a timestamp that
nothing could read back. Without `Syncable` the column reader is used and the
timestamp is visible.

`last_mf_synced_at` was unaffected because `Syncable` does not define it — which is
why an earlier probe showed one populated and the other blank, and looked like a
mystery.

## The stats were not worth wiring

`KiteItem::Syncer` fills `sync.sync_stats` (`total_accounts`, `linked_accounts`,
`holdings_count`, `errors`). Nothing in the UI reads that JSON blob, there is no
sync-history page (`SyncsController` only has `cancel`), and
`Sync.visible` only surfaces syncs under 5 minutes old. Wiring it up would have
populated a field nobody displays, on a path that already works.

## To restore

1. Move `syncer.rb` and `sync_complete_event.rb` to `app/models/kite_item/`
2. Re-add `include Syncable` to `KiteItem`
3. Have `Kite::SyncPortfolioJob` call `kite_item.sync_later` instead of
   `import_latest_kite_data`
4. Delete `KiteItem::Importer#schedule_balance_syncs` — `Account::Syncer` is what
   should drive balance materialization once the item itself goes through `Sync`