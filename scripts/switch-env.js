const fs = require('fs');
const path = require('path');

// Default to staging if no environment argument is specified
const env = (process.argv[2] || 'staging').toLowerCase();

const validEnvs = ['staging', 'prod'];
if (!validEnvs.includes(env)) {
  console.error(`[env] Invalid environment: "${env}". Allowed values: staging, prod.`);
  process.exit(1);
}

const rootDir = path.resolve(__dirname, '..');
const sourceFile = path.join(rootDir, `.env.${env}`);
const targetFile = path.join(rootDir, '.env');

try {
  if (!fs.existsSync(sourceFile)) {
    console.error(`[env] Source environment file "${sourceFile}" does not exist.`);
    process.exit(1);
  }

  fs.copyFileSync(sourceFile, targetFile);
  
  const projectRef = env === 'staging' ? 'qqiiznmqxfoamqytjica' : 'rwxelulyapjgaarlwkus';
  console.log(`[env] Switched to ${env.toUpperCase()} (${projectRef}.supabase.co)`);
} catch (error) {
  console.error(`[env] Error switching environment:`, error.message);
  process.exit(1);
}
