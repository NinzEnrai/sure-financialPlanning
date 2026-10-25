# Task 03 — Sure Standards Harness plugin bundle

**Owner:** lead
**Dependencies:** none (static hardening)
**Write scope:** `.dsh/sure-standards/` (package.json, cordis.patch.yml, index.js, locale/*.json, icon.svg)

## Goal

A profile-installable Harness bundle that registers one `systemPrompt` section carrying the Sure
engineering standards for agent sessions working in the Sure checkout.

## Verified facts this design rests on

- `cordis_inspect_query` host `Service` → `systemPrompt.section(section: PromptSection): () => void`
  registers an ordered prompt section in the calling context's scope and returns the Cordis effect
  disposer. `PromptSection = { name, order, text, interpolate?, complete? }`.
- `Config.listConfigs` on this profile shows a Loader tree of 212 entries and the bundles in
  `package.json` `dsh.profile.bundles`; a bundle is a package whose `package.json` declares
  `dsh.bundle.patch`.
- `DSH_PROFILE=desktop`, `DSH_PROFILE_DIR=C:\Users\Ninz\.dsh\profiles\desktop`.

## Deliverable

- `.dsh/sure-standards/package.json` — `@local/sure-standards`, `type: module`, exports `.`,
  `./locale/*.json`, `./icon`; `dsh.bundle.patch` points at the patch.
- `.dsh/sure-standards/cordis.patch.yml` — inserts row `sure-standards` with config
  `sectionName: sure_engineering_standards`, `order: 120`.
- `.dsh/sure-standards/index.js` — `inject = ['systemPrompt']`, `apply(ctx, config)` registers the
  section; the section body is read from the repository brief file through the optional `fs`
  service, falling back to an explicit "brief unavailable" placeholder.
- `.dsh/sure-standards/locale/en.json`, `.dsh/sure-standards/icon.svg` — display resources.

## Acceptance

- [x] `node --check index.js` exits 0
- [x] `package.json` and `locale/en.json` parse as JSON; patch row name == package name
- [x] icon.svg is well-formed SVG, 605 bytes (< 256 KiB)
- [ ] installed into the `desktop` profile via `plugin_manager install_bundle` with an absolute path
- [ ] row active, not failed/overridden
- [ ] section visible in a live agent session in this workspace
