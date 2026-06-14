// Tests/playwright/harness.ts
//
// Shared e2e scaffolding helpers for the Playwright configs.
//
// Why a shared module now (the configs used to duplicate this on purpose):
// the old worry was that importing a setup module runs its side effects at
// import time, before the config body, creating hoist-ordering surprises.
// This module deliberately has NO top-level side effects — it only declares
// constants and exports functions. The scaffold/build work happens when a
// config CALLS `prepareDemo()` at its own top level, i.e. the exact same point
// (and order) the inline `execFileSync` calls used to run. So the ordering is
// unchanged; only the duplicated body moved here.
//
// Persistence: instead of `mkdtempSync` (a fresh, cold .build every run), each
// demo lives in a stable, gitignored dir under `.e2e-cache/<key>/demo`. The
// project — and crucially its `.build` — survives between runs, so SwiftPM does
// an incremental rebuild (seconds) instead of recompiling the whole WASM graph
// (minutes). Set SWIFLOW_E2E_CLEAN=1 to force a fresh scaffold + cold build.
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  rmSync,
  statSync,
} from "node:fs";
import { createHash } from "node:crypto";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));

export const REPO_ROOT = resolve(__dirname, "..", "..");
export const SWIFLOW = join(REPO_ROOT, ".build", "release", "swiflow");

// Persistent, gitignored cache root. Survives between runs.
const CACHE_ROOT = join(REPO_ROOT, ".e2e-cache");

// Force a clean scaffold + cold build. `npm run test:clean` sets this.
const CLEAN = process.env.SWIFLOW_E2E_CLEAN === "1";

/** Build the release `swiflow` CLI if it isn't already present. */
export function ensureCli(): void {
  if (!existsSync(SWIFLOW)) {
    console.log("[e2e] building swiflow CLI (release) for the harness...");
    execFileSync("swift", ["build", "-c", "release", "--product", "swiflow"], {
      cwd: REPO_ROOT,
      stdio: "inherit",
    });
  }
}

/**
 * A stamp that changes whenever the swiflow binary does. The binary embeds the
 * project templates, so a rebuilt CLI means the scaffolded sources may differ —
 * which must invalidate a cached demo. Size+mtime is enough to detect a rebuild
 * without hashing the ~19 MB binary on every config load.
 */
function cliStamp(): string {
  const st = statSync(SWIFLOW);
  return createHash("sha256")
    .update(`${st.size}:${st.mtimeMs}`)
    .digest("hex");
}

export interface DemoOptions {
  /** Sub-dir under `.e2e-cache` and stamp namespace, e.g. "counter"/"router"/"sw". */
  key: string;
  /** Passed as `swiflow init --template <template>` (omit for default HelloWorld). */
  template?: string;
  /** Run a release `swiflow build` after scaffolding (the SW demo needs it). */
  release?: boolean;
}

/**
 * Ensure a persistent demo project exists and return its path.
 *
 * Reuses `.e2e-cache/<key>/demo` (and its `.build`) across runs. Re-scaffolds
 * only when the CLI binary changed (stamp mismatch) or SWIFLOW_E2E_CLEAN=1.
 * Framework-source edits don't need a re-scaffold: `--swiflow-source` is a local
 * path dependency, so SwiftPM's incremental build picks them up on the next
 * `swiflow dev`/`build`.
 */
export function prepareDemo(opts: DemoOptions): string {
  const dir = join(CACHE_ROOT, opts.key);
  const project = join(dir, "demo");

  // Playwright evaluates this config once in the main process AND once per worker
  // process. Only the main process starts the webServer (and so needs the demo
  // scaffolded + built); workers just run specs against the already-served files,
  // so they only need the path back. Playwright sets TEST_WORKER_INDEX in workers
  // (unset in the main process) — gate the heavy work on it to skip the otherwise
  // redundant once-per-worker rebuild.
  if (process.env.TEST_WORKER_INDEX !== undefined) {
    return project;
  }

  ensureCli();
  const stampFile = join(dir, ".cli-stamp");
  const stamp = cliStamp();

  const stale =
    CLEAN ||
    !existsSync(project) ||
    !existsSync(stampFile) ||
    readFileSync(stampFile, "utf8").trim() !== stamp;

  if (stale) {
    const why = CLEAN ? "SWIFLOW_E2E_CLEAN=1" : "stale or missing";
    console.log(`[e2e] (re)scaffolding "${opts.key}" demo (${why}) → ${project}`);
    rmSync(dir, { recursive: true, force: true });
    mkdirSync(dir, { recursive: true });
    const args = ["init", "demo", "--path", dir, "--swiflow-source", REPO_ROOT];
    if (opts.template) args.splice(2, 0, "--template", opts.template);
    execFileSync(SWIFLOW, args, { stdio: "inherit" });
    writeFileSync(stampFile, stamp);
  } else {
    console.log(
      `[e2e] reusing cached "${opts.key}" demo → ${project} ` +
        `(set SWIFLOW_E2E_CLEAN=1 to force a rebuild)`,
    );
  }

  if (opts.release) {
    // Release WASM. Cold this is ~3 min; with a reused .build it's a fast
    // incremental relink. Always run it so the manifest + SW stamp are current.
    console.log(`[e2e] swiflow build (release) for "${opts.key}" demo...`);
    execFileSync(SWIFLOW, ["build", "--path", project], {
      stdio: "inherit",
      cwd: project,
    });
  }

  return project;
}
