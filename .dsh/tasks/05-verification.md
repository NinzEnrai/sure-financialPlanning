# Task 05 (Lead) — Verification of the delivered bundle

## Static checks
- [ ] every `.js` file parses (`node --check`) — client.js included
- [ ] `package.json` is valid JSON; `cordis.patch.yml` row name matches the package name
- [ ] `locale/en.json` valid JSON with `meta.title` / `meta.description`
- [ ] `icon.svg` is well-formed SVG, < 256 KiB
- [ ] `files` / `exports` cover every runtime file

## Runtime checks
- [ ] `plugin_manager list_plugins` shows the row active (not failed / overridden)
- [ ] `plugin_manager list_bundles` shows the bundle installed
- [ ] reinstall with the corrected text yields `application: applied`
- [ ] `cordis_inspect_query` Service/systemPrompt confirms the section registration is live

## Behaviour checks (final acceptance)
- [ ] a fresh agent turn in this workspace reports the Sure standards section present in its
      assembled prompt (verify via a spawned teammate that reads its own instructions, or the
      `systemPrompt` assembly path)
- [ ] the section is scoped so it does not leak into unrelated workspaces
- [ ] the injected text carries no float-money example and no unverified command

## Reporting
- [ ] final answer states: install path, bundle id, row id, exact verification commands, what was
      verified vs. unverified, and the restart requirement if any

