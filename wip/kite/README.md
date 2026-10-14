# Kite / Zerodha integration — notes (files now live in `app/`)

Promoted out of quarantine on 2026-10-13. Nothing in this directory is loaded
by the app any more; these two files are kept as a record of intent and of the
schedules the jobs run on.

## Why it was quarantined

Eager-loading it crashed **every** boot with:

```
app/models/kite_item.rb:15: uninitialized constant KiteItem::Provided (NameError)
```

`Provided` and `Unlinking` are per-provider concerns (`SnaptradeItem::Provided`,
etc.) — the package shipped neither, and `Syncable` expects `perform_sync(sync)`
which the model never defined (it defined `import_latest_kite_data` instead).

Four concerns were missing, not the three originally listed: `Syncable` also
resolves `self.class::SyncCompleteEvent`, so omitting that one fails later, at
broadcast time rather than boot.

All four now ship in `app/models/kite_item/`.

## Where things live

| Path | What |
| --- | --- |
| `app/models/kite_item.rb`, `kite_account.rb`, `kite_item/*.rb` | models + concerns |
| `app/models/provider/kite/*.rb` | HTTP client, auth, holdings/trades/MF syncs |
| `app/controllers/kite/callbacks_controller.rb` | Zerodha redirect target |
| `app/controllers/settings/kite_connections_controller.rb` | settings page |
| `app/jobs/kite/*.rb` | portfolio sync, token-expiry check |
| `app/services/kite/sync_scheduler.rb` | sidekiq-cron registration |
| `db/migrate/20261013000100_*`, `20261013000200_*` | schema |

`Provider` is a **class** in this app (`app/models/provider.rb`), not a module —
so the provider files reopen it as `class Provider`.

## Credentials: environment, not database

`KITE_API_KEY` / `KITE_API_SECRET` are read from the environment and are **not**
stored. `kite_items` has no such columns.

The reason is backup surface, not paranoia: `pg_dump` captures every column, so
anything persisted ends up in `sure-good.dump` and in any restore onto another
machine. `/etc/sure/.env` does not. They are also long-lived, so a leaked copy
stays valid indefinitely.

The daily `access_token` **is** stored, because the Sidekiq jobs must read it
across processes and the browser login rotates it every trading day. It is
encrypted when ActiveRecord encryption is configured, plaintext otherwise —
acceptable only because of that day-scoped lifetime.

Add to `/etc/sure/.env` on the host:

```
KITE_API_KEY=...
KITE_API_SECRET=...
```

## Migrations — the trap that broke this twice

1. **Re-dated.** They were stamped `20260101…` while `db/schema.rb` sat at
   `2026_10_08_120000`. Anything at or below the schema version is treated as
   already applied, so `kite_items`, `kite_accounts` and `securities.isin` were
   never created — silently. They are now `20261013…`.
2. **`db:migrate` will load `db/schema.rb` instead of running migrations** when
   the database is empty, and `ActiveRecord::Schema.define` back-fills
   `schema_migrations` — so every migration reports `up` and the task prints
   *nothing*. If you edit a migration here, delete `db/schema.rb` first or the
   change will appear to apply and silently not.

## Known limitations

- **`Provider::Kite::Client` throttles with class-level process-local state.** Fine
  for a single worker. With multiple worker processes each keeps its own token
  bucket and they will jointly exceed Kite's ~3 req/sec cap, which risks a
  temporary ban. Move to a Redis-backed counter (Sure already runs Redis for
  Sidekiq) before scaling out.
- **`Provider::Kite::HoldingsSync` exchange mapping and `IndianNumberFormatter`
  are unexercised.** Zerodha exchange codes are mapped to MIC codes; the
  securities market-data jobs still expect the existing providers.
- **The full browser round trip has never been run** — login, redirect, token
  exchange, account provisioning and the first real sync. Only the client error
  handling has been verified against Zerodha live (a 403 `TokenException` on a
  placeholder token).
- **`kite_accounts.currency` defaults to `INR`** while the demo family's base
  currency is `USD`. Holdings are stored in their own currency and converted for
  display, which is correct, but the FIRE/wealth widgets assume a single family
  currency and will read oddly until a family is actually set to INR.
- **`Kite::SyncScheduler` registers cron jobs on Sidekiq startup.** If
  registration fails it logs and continues rather than blocking boot.

## Schedules

`sidekiq_schedule_additions.yml` (below) is superseded by
`Kite::SyncScheduler`, which registers the same two jobs using the
`Sidekiq::Cron::Job.create` pattern from `AutoSyncScheduler`. Nothing reads the
YAML; it is kept only as the record of intent.

| Job | Cron |
| --- | --- |
| `Kite::BulkSyncSchedulerJob` | `*/20 * * * *` |
| `Kite::CheckTokenExpiryJob` | `*/15 * * * *` |