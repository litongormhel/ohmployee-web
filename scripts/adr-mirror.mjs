// ADR-001 read-only mirror: check freshness / sync from the mobile repo.
// Usage: node scripts/adr-mirror.mjs check|sync
// Source of truth stays in the mobile repo. Override its location with OHM_MOBILE_REPO.
// `check` never fails the calling npm script (always exit 0); it prints ADR_MIRROR_STATUS.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const mode = process.argv[2];
if (!['check', 'sync'].includes(mode)) {
  console.error('Usage: node scripts/adr-mirror.mjs check|sync');
  process.exit(1);
}

if (process.env.VERCEL || process.env.CI) {
  console.log('[adr] CI/Vercel detected. Skipping ADR mirror check.');
  process.exit(0);
}

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const mobileRepo = path.resolve(process.env.OHM_MOBILE_REPO || path.join(root, '..', 'OHMployee'));
const SRC_REL = '.ai/architecture_locks/ADR-001-ohmployee-system-architecture.md';
const srcFile = path.join(mobileRepo, SRC_REL);
const mirrorFile = path.join(root, 'docs/architecture/_mirror/ADR-001-ohmployee-system-architecture.md');

const normalize = (s) => s.replace(/\r\n/g, '\n');
const sha256 = (s) => crypto.createHash('sha256').update(normalize(s), 'utf8').digest('hex');
const git = (args, timeout = 5000) =>
  execFileSync('git', ['-C', mobileRepo, ...args], {
    encoding: 'utf8',
    timeout,
    stdio: ['ignore', 'pipe', 'ignore'],
    env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
  }).trim();

function status(code, detail) {
  const line = `ADR_MIRROR_STATUS: ${code}${detail ? ` — ${detail}` : ''}`;
  if (code === 'FRESH' || code === 'SYNCED') console.log(`[adr] ${line}`);
  else console.warn(`\n[adr] ⚠️  ${line}\n[adr] Fix: npm run sync:adr (see AGENTS.md)\n`);
}

function readMirror() {
  if (!fs.existsSync(mirrorFile)) return null;
  const text = normalize(fs.readFileSync(mirrorFile, 'utf8'));
  const end = text.indexOf('-->\n');
  if (!text.startsWith('<!--') || end === -1) return { header: {}, body: text };
  const header = Object.fromEntries(
    text.slice(4, end).split('\n')
      .map((l) => l.match(/^\s*([a-z0-9_]+):\s*(.*)$/))
      .filter(Boolean)
      .map((m) => [m[1], m[2].trim()]),
  );
  return { header, body: text.slice(end + 4) };
}

function sourceCommit() {
  try {
    const hash = git(['log', '-1', '--format=%h %cI', '--', SRC_REL]) || 'untracked';
    const dirty = git(['status', '--porcelain', '--', SRC_REL]) ? ' +uncommitted-changes' : '';
    return hash + dirty;
  } catch {
    return 'unknown (git unavailable)';
  }
}

// Warn if the local mobile clone is behind its remote for the ADR file. Never fatal.
function remoteCheck() {
  try {
    git(['fetch', '--quiet'], 10000);
  } catch {
    console.warn('[adr] Remote check NOT VERIFIED (git fetch failed / offline).');
    return;
  }
  try {
    const behind = Number(git(['rev-list', '--count', 'HEAD..@{u}', '--', SRC_REL]));
    if (behind > 0) {
      console.warn(`\n[adr] ⚠️  Mobile repo is ${behind} commit(s) behind remote for the ADR. Run: git -C "${mobileRepo}" pull\n`);
    } else {
      console.log('[adr] Remote check: mobile ADR is up to date with upstream.');
    }
  } catch {
    console.warn('[adr] Remote check NOT VERIFIED (no upstream branch configured).');
  }
}

const sourceExists = fs.existsSync(srcFile);

if (mode === 'sync') {
  if (!sourceExists) {
    console.error(`[adr] Source not found: ${srcFile}\n[adr] Set OHM_MOBILE_REPO to the mobile repo path.`);
    process.exit(1);
  }
  remoteCheck();
  const body = normalize(fs.readFileSync(srcFile, 'utf8'));
  const prev = readMirror();
  const header = [
    '<!--',
    'ADR-MIRROR: DO NOT EDIT. Read-only copy. Edit the ADR in the mobile repo, then run `npm run sync:adr`.',
    `source: OHMployee/${SRC_REL}`,
    `source_commit: ${sourceCommit()}`,
    `source_sha256: ${sha256(body)}`,
    `synced_at: ${new Date().toISOString()}`,
    '-->',
    '',
  ].join('\n');
  fs.mkdirSync(path.dirname(mirrorFile), { recursive: true });
  fs.writeFileSync(mirrorFile, header + body, 'utf8');
  const from = prev?.header?.source_commit || 'none';
  status('SYNCED', `${from} → ${sourceCommit()}`);
  process.exit(0);
}

// mode === 'check'
const mirror = readMirror();
if (!mirror) {
  status('MIRROR_MISSING', path.relative(root, mirrorFile));
  process.exit(0);
}
if (mirror.header.source_sha256 && sha256(mirror.body) !== mirror.header.source_sha256) {
  status('MIRROR_EDITED', 'mirror body was edited by hand; re-sync to restore');
  process.exit(0);
}
if (!sourceExists) {
  status('NOT_VERIFIED', `mobile repo not found at ${mobileRepo}; using mirror (${mirror.header.source_commit || 'unknown'})`);
  process.exit(0);
}
remoteCheck();
const srcHash = sha256(fs.readFileSync(srcFile, 'utf8'));
if (srcHash !== mirror.header.source_sha256) {
  status('STALE', `mirror ${mirror.header.source_commit || 'unknown'} ≠ source ${sourceCommit()}`);
} else {
  status('FRESH', mirror.header.source_commit);
}
process.exit(0);
