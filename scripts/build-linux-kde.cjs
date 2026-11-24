'use strict';

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
if (process.platform !== 'linux') throw new Error('The KDE RPM candidate must be built on Linux');

function run(command, args) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', env: process.env });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}

run('python3', ['scripts/check-tls-locks.py']);
run('npm', ['run', 'build']);
run('cargo', [
  'build', '--locked', '--release', '--manifest-path', 'src-tauri/Cargo.toml',
  '--bin', 'xjaus_backend', '-j', '8',
]);

const backend = path.join(root, 'src-tauri', 'target', 'release', 'xjaus_backend');
if (!fs.existsSync(backend) || !fs.statSync(backend).isFile()) {
  throw new Error('Cargo did not produce src-tauri/target/release/xjaus_backend');
}
const buildDir = path.join(root, 'build', 'kde-linux');
const outputDir = path.join(root, 'release', 'linux-kde');
run('cmake', [
  '-S', 'kde-linux', '-B', buildDir, '-DCMAKE_BUILD_TYPE=Release',
  `-DXJAUS_BACKEND_PATH=${backend}`,
]);
run('cmake', ['--build', buildDir, '--parallel', '2']);
run('cpack', ['--config', path.join(buildDir, 'CPackConfig.cmake'), '-B', outputDir]);

const rpms = fs.readdirSync(outputDir).filter(name => name.endsWith('.rpm'));
if (rpms.length !== 1) throw new Error(`Expected one Fedora RPM candidate, found ${rpms.length}`);
console.log(`KDE RPM candidate ready: release/linux-kde/${rpms[0]}`);
