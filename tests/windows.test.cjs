const { execFile } = require('node:child_process');
const path = require('node:path');
const { promisify } = require('node:util');
const { test } = require('node:test');

const run = promisify(execFile);

test('published Windows app opens and exports through its native controls', {
  skip: process.platform !== 'win32',
  timeout: 85000,
}, async () => {
  const executable = path.resolve(process.env.PLANNER_EXE ?? 'artifacts/Anime-Filename-Planner.exe');
  try {
    const { stdout } = await run('powershell.exe', [
      '-NoProfile', '-NonInteractive', '-STA', '-File', path.join(__dirname, 'windows-ui.ps1'), '-Executable', executable,
    ], { timeout: 80000 });
    process.stdout.write(stdout);
  } catch (error) {
    if (error.stdout) process.stdout.write(error.stdout);
    if (error.stderr) process.stderr.write(error.stderr);
    throw error;
  }
});
