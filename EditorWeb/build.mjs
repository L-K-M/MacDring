import { build } from 'esbuild';
import { mkdirSync, statSync } from 'node:fs';

/**
 * Deterministic production bundle: fixed esbuild + dependency versions
 * (lockfile) and no time/hash-based output. Rebuilding from the same
 * lockfile must produce byte-identical dist/ output — CI diffs it.
 */
const shared = {
  bundle: true,
  minify: true,
  sourcemap: true,
  target: ['safari16', 'es2022'],
  logLevel: 'info',
};

mkdirSync('dist', { recursive: true });

await build({
  ...shared,
  entryPoints: ['src/main.ts'],
  format: 'iife',
  outfile: 'dist/editor.js',
  loader: { '.css': 'css' },
});

for (const file of ['dist/editor.js', 'dist/editor.css']) {
  const { size } = statSync(file);
  console.log(`${file}: ${(size / 1024).toFixed(1)} KiB`);
}
