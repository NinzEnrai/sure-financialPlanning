/**
 * @local/sure-standards — Harness Host plugin.
 *
 * Registers one system-prompt section carrying the Sure engineering standards
 * for this repository. The section is registered on the plugin's own context,
 * so Cordis disposes it when the row is disabled or the profile unmounts.
 */

/** The workspace this plugin applies to; compared case-insensitively. */
const DEFAULT_ROOT = 'sure-financialPlanning';

/** Injected when no repository brief has been written yet. */
const PLACEHOLDER = [
  'Sure engineering standards are not available: no brief file was found for this workspace.',
  'Do not assume any rule from a previous session; ask for the repository brief instead.',
].join('\n');

export const inject = ['systemPrompt'];

export const Config = {
  sectionName: 'sure_engineering_standards',
  order: 120,
  appliesTo: DEFAULT_ROOT,
  brief: '.dsh/tasks/02-standards-draft.md',
  headline: 'Sure repository engineering standards',
  maxBriefChars: 60000,
};

/**
 * Resolve the workspace root without taking a hard dependency on the
 * workingDirectory service, which is absent in headless compositions.
 */
function resolveRoot(ctx) {
  const service = ctx.get('workingDirectory');
  if (service && typeof service.defaultDirectory === 'string') return service.defaultDirectory;
  return process.cwd();
}

function normalize(value) {
  return String(value).replace(/\\/g, '/').replace(/\/+$/, '').toLowerCase();
}

function applies(root, marker) {
  if (!marker) return true;
  return normalize(root).endsWith('/' + normalize(marker));
}

export function apply(ctx, config) {
  const options = { ...Config, ...config };
  const root = resolveRoot(ctx);
  const governed = applies(root, options.appliesTo);

  ctx.logger?.info?.(
    governed
      ? '[sure-standards] active for ' + root
      : '[sure-standards] inactive: ' + root + ' is outside ' + options.appliesTo,
  );

  ctx.systemPrompt.section({
    name: options.sectionName,
    order: options.order,
    text: governed ? buildSection(ctx, options, root) : '',
  });
}

function buildSection(ctx, options, root) {
  const brief = readBrief(ctx, options.brief, root, options.maxBriefChars);
  const body = brief ?? PLACEHOLDER;

  return [
    '## ' + options.headline,
    '',
    'This checkout is **Sure** — a self-hosted personal finance application (community fork of',
    'Maybe Finance) built on Ruby on Rails 8, Hotwire, PostgreSQL and Tailwind CSS. The standards',
    'below are mandatory for every change made under `' + root + '`.',
    '',
    body.trim(),
  ].join('\n');
}

/**
 * Read the optional repository-authored brief through the filesystem seam.
 * The service and its methods are synchronous; anything else means the seam is
 * shaped differently than assumed, so the placeholder is used instead.
 */
function readBrief(ctx, relativePath, root, maxChars) {
  try {
    const fs = ctx.get('fs');
    if (!fs || typeof fs.readText !== 'function' || typeof fs.resolve !== 'function') return null;

    const target = fs.resolve(relativePath, { cwd: root });
    if (!target || typeof target.then === 'function') return null;

    const text = fs.readText(target);
    if (typeof text !== 'string' || !text.trim()) return null;

    const limit = Number.isFinite(maxChars) && maxChars > 0 ? maxChars : 60000;
    return text.length > limit ? text.slice(0, limit) + '\n\n[standards brief truncated]' : text;
  } catch {
    return null;
  }
}
