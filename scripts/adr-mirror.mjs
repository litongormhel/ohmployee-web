// ADR read-only mirror: check freshness / sync from the mobile repo.
// Supports ADR-001 and ADR-002.
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

const ADR_FILES = [
  {
    id: 'ADR-001',
    srcRel: '.ai/architecture_locks/ADR-001-ohmployee-system-architecture.md',
    mirrorRel: 'docs/architecture/_mirror/ADR-001-ohmployee-system-architecture.md',
  },
  {
    id: 'ADR-002',
    srcRel: 'docs/architecture/adr002_plantilla_import_store_identity_and_governance.md',
    mirrorRel: 'docs/architecture/_mirror/adr002_plantilla_import_store_identity_and_governance.md',
  },
];

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

function readMirror(mirrorFile) {
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

function sourceCommit(srcRel) {
  try {
    const hash = git(['log', '-1', '--format=%h %cI', '--', srcRel]) || 'untracked';
    const dirty = git(['status', '--porcelain', '--', srcRel]) ? ' +uncommitted-changes' : '';
    return hash + dirty;
  } catch {
    return 'unknown (git unavailable)';
  }
}

// Warn if the local mobile clone is behind its remote for any ADR file. Never fatal.
function remoteCheck() {
  try {
    git(['fetch', '--quiet'], 10000);
  } catch {
    console.warn('[adr] Remote check NOT VERIFIED (git fetch failed / offline).');
    return;
  }
  try {
    const srcPaths = ADR_FILES.map((f) => f.srcRel);
    const behind = Number(git(['rev-list', '--count', 'HEAD..@{u}', '--', ...srcPaths]));
    if (behind > 0) {
      console.warn(`\n[adr] ⚠️  Mobile repo is ${behind} commit(s) behind remote for ADR files. Run: git -C "${mobileRepo}" pull\n`);
    } else {
      console.log('[adr] Remote check: mobile ADRs are up to date with upstream.');
    }
  } catch {
    console.warn('[adr] Remote check NOT VERIFIED (no upstream branch configured).');
  }
}

if (mode === 'sync') {
  remoteCheck();
  const results = [];
  for (const item of ADR_FILES) {
    const srcFile = path.join(mobileRepo, item.srcRel);
    const mirrorFile = path.join(root, item.mirrorRel);
    if (!fs.existsSync(srcFile)) {
      console.error(`[adr] Source not found: ${srcFile}`);
      continue;
    }
    const body = normalize(fs.readFileSync(srcFile, 'utf8'));
    const prev = readMirror(mirrorFile);
    const header = [
      '<!--',
      `ADR-MIRROR: DO NOT EDIT. Read-only copy of ${item.id}. Edit in mobile repo, then run \`npm run sync:adr\`.`,
      `source: OHMployee/${item.srcRel}`,
      `source_commit: ${sourceCommit(item.srcRel)}`,
      `source_sha256: ${sha256(body)}`,
      `synced_at: ${new Date().toISOString()}`,
      '-->',
      '',
    ].join('\n');
    fs.mkdirSync(path.dirname(mirrorFile), { recursive: true });
    fs.writeFileSync(mirrorFile, header + body, 'utf8');
    const from = prev?.header?.source_commit || 'none';
    results.push(`${item.id}: ${from} → ${sourceCommit(item.srcRel)}`);
  }
  status('SYNCED', results.join('; '));
  process.exit(0);
}

// mode === 'check'
const mobileExists = fs.existsSync(mobileRepo);
if (mobileExists) {
  remoteCheck();
}

let anyStale = false;
let anyMissing = false;
let anyEdited = false;
let unverified = !mobileExists;
const freshList = [];

for (const item of ADR_FILES) {
  const srcFile = path.join(mobileRepo, item.srcRel);
  const mirrorFile = path.join(root, item.mirrorRel);
  const mirror = readMirror(mirrorFile);

  if (!mirror) {
    anyMissing = true;
    status('MIRROR_MISSING', `${item.id}: ${path.relative(root, mirrorFile)}`);
    continue;
  }
  if (mirror.header.source_sha256 && sha256(mirror.body) !== mirror.header.source_sha256) {
    anyEdited = true;
    status('MIRROR_EDITED', `${item.id}: mirror body edited by hand; run npm run sync:adr`);
    continue;
  }
  if (!fs.existsSync(srcFile)) {
    unverified = true;
    status('NOT_VERIFIED', `${item.id}: mobile source not found; using mirror (${mirror.header.source_commit || 'unknown'})`);
    continue;
  }
  const srcHash = sha256(fs.readFileSync(srcFile, 'utf8'));
  if (srcHash !== mirror.header.source_sha256) {
    anyStale = true;
    status('STALE', `${item.id}: mirror ${mirror.header.source_commit || 'unknown'} ≠ source ${sourceCommit(item.srcRel)}`);
  } else {
    freshList.push(`${item.id} (${mirror.header.source_commit || 'ok'})`);
  }
}

if (!anyStale && !anyMissing && !anyEdited && !unverified) {
  status('FRESH', freshList.join(', '));
}

process.exit(0);
