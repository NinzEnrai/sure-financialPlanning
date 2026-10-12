# Kite / Zerodha integration — quarantined, work in progress

Moved out of `app/`, `config/` and `db/migrate/` on 2026-10-12 because the
integration was never completed, and eager-loading it crashed **every** boot
with:

```
app/models/kite_item.rb:15: uninitialized constant KiteItem::Provided (NameError)
```

`Provided` and `Unlinking` are per-provider concerns (`SnaptradeItem::Provided`,
etc.) — this package ships neither, and `Syncable` expects `perform_sync(sync)`
which the model never defines (it defines `import_latest_kite_data` instead).
Compare `app/models/snaptrade_item/`, which has `provided.rb`, `unlinking.rb`,
`syncer.rb` and `sync_complete_event.rb`.

## Layout

| Path here | Goes back to |
| --- | --- |
| `models/kite_item.rb`, `kite_account.rb`, `kite_connection.rb`, `kite_item/importer.rb` | `app/models/` |
| `controllers/`, `controllers/kite/`, `controllers/kite_connections_controller.rb` | `app/controllers/`, `app/controllers/settings/` |
| `jobs/kite/` | `app/jobs/` |
| `providers/kite/` | `app/services/provider/` |
| `migrations/*.rb` | `db/migrate/` |
| `indian_number_formatter.rb` | `lib/` |
| `sidekiq_schedule_additions.yml` | merged into `config/sidekiq_schedule.yml` |

`wip/` is not an autoload path, so nothing here is loaded by the app.

## To restore

1. Move the files back per the table above.
2. Write the three missing concerns under `app/models/kite_item/`
   (`provided.rb`, `unlinking.rb`, `syncer.rb`), modelled on
   `app/models/snaptrade_item/`.
3. Rename `KiteItem#import_latest_kite_data` to `perform_sync(sync)`, or add a
   `perform_sync` that delegates to it — `Syncable` calls that name.
4. **Re-date the migrations.** This is the trap that made them silently no-op:
   they are stamped `20260101…`, but `db/schema.rb` sits at
   `2026_10_08_120000`. Anything at or below the schema version is marked
   applied by `db:schema:load` and never executes, so `kite_items`,
   `kite_accounts` and `kite_connections` were never created. Renumber them to
   a current timestamp (e.g. `20261013…`) or they will stay dead.
5. Change `ActiveRecord::Migration[7.1]` to `[8.1]` to match
   `config.load_defaults 8.1`.
6. Merge `sidekiq_schedule_additions.yml` into `config/sidekiq_schedule.yml` —
   it was never merged, so the sync jobs were never scheduled.

Until step 4 is done, any code that touches these models will fail at query
time regardless of the rest being correct.