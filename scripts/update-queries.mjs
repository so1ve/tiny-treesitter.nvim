import { spawnSync } from "node:child_process";
import { cp, mkdir, mkdtemp, rename, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const upstreamUrl = process.env.QUERY_SOURCE_URL ?? "https://github.com/arborist-ts/queries";
const upstreamRef = process.env.QUERY_SOURCE_REF ?? "main";
const dryRun = process.env.TINY_TREESITTER_UPDATE_QUERIES_DRY_RUN === "1" || process.env.TINY_TREESITTER_UPDATE_QUERIES_DRY_RUN === "true";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const target = path.join(repoRoot, "runtime", "queries");

function log(message) {
  console.log(`[update-queries] ${message}`);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    ...options,
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    const stderr = result.stderr.trim();
    throw new Error(`${command} ${args.join(" ")} failed${stderr ? `: ${stderr}` : ""}`);
  }

  return result.stdout;
}

async function main() {
  const sourceUrl = upstreamUrl.replace(/\.git$/, "");
  const archiveUrl = `${sourceUrl}/archive/${upstreamRef}.tar.gz`;

  if (dryRun) {
    log(`dry-run: would replace ${target}`);
    log(`dry-run: source ${archiveUrl}`);

    return;
  }

  const workDir = await mkdtemp(path.join(tmpdir(), "tiny-ts-runtime-"));
  const archive = path.join(workDir, "queries.tar.gz");
  const sourceRoot = path.join(workDir, "source");
  const source = path.join(sourceRoot, "queries");
  const nextTarget = path.join(repoRoot, "runtime", `queries.${process.pid}.next`);

  await rm(nextTarget, { recursive: true, force: true });
  await mkdir(sourceRoot, { recursive: true });

  try {
    log(`downloading ${archiveUrl}`);
    run("curl", [
      "--silent",
      "--fail",
      "--show-error",
      "--retry",
      "7",
      "-L",
      archiveUrl,
      "--output",
      archive,
    ]);

    log("extracting archive");
    run("tar", ["-xzf", archive, "--strip-components=1", "-C", sourceRoot]);

    await rm(path.join(source, "scripts"), { recursive: true, force: true });

    log(`copying ${source}`);
    await cp(source, nextTarget, { recursive: true });

    log(`replacing ${target}`);
    await rm(target, { recursive: true, force: true });
    try {
      await rename(nextTarget, target);
    }
    catch (error) {
      log(`rename failed (${error.code ?? error.message}); falling back to recursive copy`);
      await cp(nextTarget, target, { recursive: true });
    }

    log(`updated runtime/queries from ${upstreamUrl} @ ${upstreamRef}`);
  } finally {
    await rm(nextTarget, { recursive: true, force: true });
    await rm(workDir, { recursive: true, force: true });
  }
}

await main();
