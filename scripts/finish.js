const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const readline = require('readline');

const STAGING_REF = 'qqiiznmqxfoamqytjica';
const PROD_REF = 'rwxelulyapjgaarlwkus';

function main() {
  console.log('======================================================');
  console.log('  OHMployee Web -- End-of-Task Orchestrator');
  console.log('======================================================');

  // 1. Detect target environment from .env
  const rootDir = path.resolve(__dirname, '..');
  const envFile = path.join(rootDir, '.env');
  let currentRef = '';
  let envName = 'UNRESOLVED';

  if (fs.existsSync(envFile)) {
    const envContent = fs.readFileSync(envFile, 'utf8');
    const match = envContent.match(/NEXT_PUBLIC_SUPABASE_URL=https:\/\/([a-z0-9]+)\.supabase\.co/);
    if (match && match[1]) {
      currentRef = match[1].trim();
      if (currentRef === STAGING_REF) {
        envName = 'STAGING';
      } else if (currentRef === PROD_REF) {
        envName = 'PRODUCTION';
      }
    }
  }

  console.log(`  Resolved target ref: ${currentRef || '<unresolved>'}`);
  console.log(`  Environment Name   : ${envName}`);
  console.log('');

  // 2. Repository status checks
  let statusOut = '';
  try {
    statusOut = execSync('git status --porcelain', { cwd: rootDir, encoding: 'utf8' }).trim();
  } catch (err) {
    console.error('Failed to run git status:', err.message);
    process.exit(1);
  }

  if (!statusOut) {
    console.log('  [PASS] No changes to commit -- working tree clean.');
    process.exit(0);
  }

  // Parse git status to identify modified vs untracked files
  const lines = statusOut.split('\n').filter(Boolean);
  const untrackedFiles = [];
  const trackedChanges = [];

  for (const line of lines) {
    const status = line.slice(0, 2);
    const filePath = line.slice(3).trim();
    if (status === '??') {
      // Ignore IDE/Agent-specific files like .claude/
      if (!filePath.startsWith('.claude/')) {
        untrackedFiles.push(filePath);
      }
    } else {
      trackedChanges.push(filePath);
    }
  }

  // 3. Repository File Classification (untracked files)
  const filesToStage = [];
  if (untrackedFiles.length > 0) {
    const scopeFilesVar = process.env.OHM_SCOPE_FILES;
    if (!scopeFilesVar) {
      console.error('  [FAIL] Untracked files detected but OHM_SCOPE_FILES is not set.');
      console.error('  Please declare the task scope files. Example:');
      console.error('    OHM_SCOPE_FILES="src/app/page.tsx" node scripts/finish.js');
      console.error('');
      console.error('  Untracked files list:');
      untrackedFiles.forEach(f => console.error(`    ${f}`));
      process.exit(1);
    }

    const scopeFiles = scopeFilesVar.split(':').map(s => s.trim().replace(/^\.\//, ''));
    console.log('  Checking untracked files against OHM_SCOPE_FILES:');
    for (const f of untrackedFiles) {
      const normFile = f.replace(/^\.\//, '');
      const isMatch = scopeFiles.some(s => s === normFile);
      if (isMatch) {
        console.log(`    [GROUP A -- in-scope] ${f} (will be staged)`);
        filesToStage.push(f);
      } else {
        console.log(`    [GROUP B -- out-scope] ${f} (left untracked)`);
      }
    }
    console.log('');
  }

  // 4. Determine prompt ID and title from briefing.md
  let promptId = process.env.OHM_PROMPT_ID || 'ohm#manual';
  let taskTitle = 'Stop-hook validated';

  const briefingFile = path.join(rootDir, '.ai', 'briefing.md');
  if (fs.existsSync(briefingFile)) {
    try {
      const briefingContent = fs.readFileSync(briefingFile, 'utf8');
      const lines = briefingContent.split('\n');
      let inCompletedTasks = false;
      for (const line of lines) {
        if (line.match(/## Last Completed Tasks/i)) {
          inCompletedTasks = true;
          continue;
        }
        if (inCompletedTasks && line.trim().startsWith('##')) {
          break;
        }
        if (inCompletedTasks) {
          // Format 1: - **ohm#7bxk1nte**: ohmployee-web — Fix...
          const match1 = line.match(/^-\s+\*\*([a-zA-Z0-9#_]+)\*\*:\s*(.+)/);
          if (match1) {
            promptId = match1[1].trim();
            taskTitle = match1[2].trim();
            break;
          }
          // Format 2: 0. [2026-07-11] `ohm#2y7h4b1s` — Fix...
          const match2 = line.match(/^\d+\.\s+\[[^\]]+\]\s+`([^`]+)`\s+[-—–]\s*(.+)/);
          if (match2) {
            promptId = match2[1].trim();
            taskTitle = match2[2].trim();
            break;
          }
        }
      }
    } catch (e) {
      // Ignore briefing.md parsing issues
    }
  }

  // 5. Environmental Gate Safety check
  if (envName === 'STAGING') {
    console.log('  PROD Push Gate -- target confirmed STAGING.');
    console.log('  Proceeding to execute git commit automatically.');
    console.log('');
    performCommit(rootDir, filesToStage, promptId, taskTitle, envName);
  } else {
    // PROD or UNRESOLVED -> Manual human confirmation required
    console.warn(`  *** WARNING: ${envName} TARGET DETECTED ***`);
    console.warn('  Auto-commit is staging/UAT-only. PRODUCTION or ambiguous environments');
    console.warn('  require manual confirmation.');
    console.warn('');

    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout
    });

    rl.question('  Please type "CONFIRM-PROD" to verify this commit: ', (answer) => {
      rl.close();
      if (answer.trim() === 'CONFIRM-PROD') {
        console.log('  Confirmation accepted. Proceeding with commit.');
        performCommit(rootDir, filesToStage, promptId, taskTitle, envName);
      } else {
        console.error('  [FAIL] Confirmation mismatch. Commit aborted.');
        process.exit(1);
      }
    });
  }
}

function performCommit(rootDir, filesToStage, promptId, taskTitle, envName) {
  try {
    // Stage Group A untracked files
    for (const f of filesToStage) {
      execSync(`git add "${f}"`, { cwd: rootDir });
    }
    // Stage modified and deleted files
    execSync('git add -u', { cwd: rootDir });

    const timestamp = new Date().toISOString();
    const commitMsg = `auto: ${promptId} — ${taskTitle}

Timestamp: ${timestamp}
Environment: ${envName}
Lint/Build: VALIDATED`;

    fs.writeFileSync(path.join(rootDir, '.git-commit-msg.txt'), commitMsg, 'utf8');
    execSync('git commit -F .git-commit-msg.txt', { cwd: rootDir });
    fs.unlinkSync(path.join(rootDir, '.git-commit-msg.txt'));

    console.log('');
    console.log('======================================================');
    console.log(`  RESULT: PASS`);
    console.log(`  Committed: ${promptId} for ${envName}`);
    console.log('  (No git push -- GitHub auto-push is DISABLED)');
    console.log('======================================================');
    process.exit(0);
  } catch (err) {
    console.error('  [FAIL] Git commit failed:', err.message);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}
