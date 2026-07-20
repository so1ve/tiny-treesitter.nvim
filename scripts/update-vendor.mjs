import { access, cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const nvimDir = path.join(repoRoot, ".vendor", "nvim-treesitter");
const arboristDir = path.join(repoRoot, ".vendor", "arborist");
const repositories = {
  arborist: "https://github.com/arborist-ts/arborist.nvim",
  "nvim-treesitter": "https://github.com/nvim-treesitter/nvim-treesitter",
};
const { values } = parseArgs({
  options: {
    "arborist-ref": { default: "main", type: "string" },
    "nvim-ref": { default: "main", type: "string" },
  },
});

function parseScalar(value) {
  const trimmed = value.trim();

  if (trimmed === "true") {
    return true;
  }

  if (trimmed === "false") {
    return false;
  }

  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.slice(1, -1);
  }

  return trimmed;
}

function parseArray(value) {
  const body = value.trim().slice(1, -1).trim();

  if (!body) {
    return [];
  }

  return body.split(",").map((item) => parseScalar(item));
}

function stripComment(line) {
  let quoted = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];

    if (char === '"' && line[index - 1] !== "\\") {
      quoted = !quoted;
    }

    if (char === "#" && !quoted) {
      return line.slice(0, index);
    }
  }

  return line;
}

function parseTomlTables(text) {
  const tables = new Map();
  let current;

  for (const rawLine of text.split(/\r?\n/)) {
    const line = stripComment(rawLine).trim();

    if (!line) {
      continue;
    }

    const section = line.match(/^\[([^\]]+)]$/);

    if (section) {
      current = {};
      tables.set(section[1], current);
      continue;
    }

    const assignment = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(.+)$/);

    if (!assignment || !current) {
      continue;
    }

    const [, key, value] = assignment;
    const trimmed = value.trim();

    current[key] = trimmed.startsWith("[") ? parseArray(trimmed) : parseScalar(trimmed);
  }

  return tables;
}

function luaTableKeys(source) {
  const keys = new Set();
  const entry = /^  (?:\["([^"]+)"\]|([A-Za-z0-9_]+))\s*=\s*\{/gm;

  for (const match of source.matchAll(entry)) {
    keys.add(match[1] ?? match[2]);
  }

  return keys;
}

function renderLuaValue(value) {
  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }

  if (Array.isArray(value)) {
    return `{ ${value.map((item) => JSON.stringify(item)).join(", ")} }`;
  }

  return JSON.stringify(value);
}

function renderParser(name, parser, revision) {
  const lines = [`  [${JSON.stringify(name)}] = {`, "    install_info = {"];

  for (const key of ["url", "branch", "location", "generate"]) {
    if (parser[key] !== undefined) {
      lines.push(`      ${key} = ${renderLuaValue(parser[key])},`);
    }
  }

  lines.push(`      revision = ${JSON.stringify(revision)},`, "    },");

  if (parser.requires !== undefined) {
    lines.push(`    requires = ${renderLuaValue(parser.requires)},`);
  }

  lines.push("  },");
  return lines.join("\n");
}

function runGit(args, context) {
  const result = spawnSync("git", args, { encoding: "utf8" });

  if (result.status !== 0) {
    throw new Error(`${context}: ${result.stderr.trim()}`);
  }

  return result.stdout.trim();
}

async function syncRepository(directory, url, ref) {
  if (!await exists(path.join(directory, ".git"))) {
    await mkdir(directory, { recursive: true });
    runGit(["init", directory], `Unable to initialize ${directory}`);
    runGit(["-C", directory, "remote", "add", "origin", url], `Unable to configure ${directory}`);
  }
  else {
    runGit(["-C", directory, "remote", "set-url", "origin", url], `Unable to configure ${directory}`);
  }

  runGit(["-C", directory, "fetch", "--depth=1", "origin", ref], `Unable to fetch ${ref} from ${url}`);
  runGit(["-C", directory, "checkout", "--detach", "FETCH_HEAD"], `Unable to check out ${ref} in ${directory}`);
}

function resolveRevision(name, parser) {
  const ref = parser.branch ? `refs/heads/${parser.branch}` : "HEAD";
  return runGit(
    ["ls-remote", "--exit-code", parser.url, ref],
    `Unable to resolve ${name} from ${parser.url}`,
  ).split(/\s+/)[0];
}

function appendToReturnedTable(source, additions) {
  const normalized = source.replace(/\r\n/g, "\n");
  const end = normalized.search(/\n}\s*$/);

  if (end < 0) {
    throw new Error("nvim-treesitter parsers.lua does not end in a returned table");
  }

  return `${normalized.slice(0, end)}\n${additions}\n${normalized.slice(end + 1)}`;
}

function appendToFiletypes(source, additions) {
  const normalized = source.replace(/\r\n/g, "\n");
  const tableStart = normalized.indexOf("local filetypes = {");
  const tableEnd = normalized.indexOf("\n}", tableStart);

  if (tableStart < 0 || tableEnd < 0) {
    throw new Error("nvim-treesitter filetypes.lua does not contain the filetypes table");
  }

  return `${normalized.slice(0, tableEnd)}\n${additions}${normalized.slice(tableEnd)}`;
}

async function exists(target) {
  try {
    await access(target);
    return true;
  }
  catch {
    return false;
  }
}

function renderUpdateSummary(previousSources, currentSources) {
  const changes = Object.entries(currentSources)
    .filter(([name, source]) => previousSources[name]?.revision !== source.revision)
    .map(([name, source]) => {
      const previousRevision = previousSources[name]?.revision;
      const repository = source.repository.replace(/\/$/, "");

      if (!previousRevision) {
        return "- [" + name + ": " + source.revision.slice(0, 7) + "]("
          + repository + "/commit/" + source.revision + ")";
      }

      return "- [" + name + ": " + previousRevision.slice(0, 7) + " → "
        + source.revision.slice(0, 7) + "](" + repository + "/compare/"
        + previousRevision + "..." + source.revision + ")";
    });

  return [
    "Automated vendor bump.",
    "",
    "## Updated sources",
    "",
    ...changes,
    "",
  ].join("\n");
}

async function updateVendor() {
  const previousSources = JSON.parse(
    await readFile(path.join(repoRoot, "vendor-sources.json"), "utf8"),
  );

  await syncRepository(nvimDir, repositories["nvim-treesitter"], values["nvim-ref"]);
  await syncRepository(arboristDir, repositories.arborist, values["arborist-ref"]);

  const nvimQueries = path.join(nvimDir, "runtime", "queries");
  const arboristRegistry = path.join(arboristDir, "registry");

  const [nvimParsers, nvimFiletypes, nvimLicense, arboristLicense, parserToml, pinsToml, filetypesToml] = await Promise.all([
    readFile(path.join(nvimDir, "lua", "nvim-treesitter", "parsers.lua"), "utf8"),
    readFile(path.join(nvimDir, "plugin", "filetypes.lua"), "utf8"),
    readFile(path.join(nvimDir, "LICENSE"), "utf8"),
    readFile(path.join(arboristDir, "LICENSE"), "utf8"),
    readFile(path.join(arboristRegistry, "parsers.toml"), "utf8"),
    readFile(path.join(arboristRegistry, "pins.toml"), "utf8"),
    readFile(path.join(arboristRegistry, "filetypes.toml"), "utf8"),
  ]);
  const nvimRevision = runGit(["-C", nvimDir, "rev-parse", "HEAD"], "Unable to read nvim-treesitter revision");
  const arboristRevision = runGit(["-C", arboristDir, "rev-parse", "HEAD"], "Unable to read arborist revision");
  const arboristParsers = parseTomlTables(parserToml);
  const arboristPins = parseTomlTables(pinsToml);
  const arboristFiletypes = parseTomlTables(filetypesToml).get("filetypes");
  const nvimNames = luaTableKeys(nvimParsers);
  const nvimFiletypeNames = luaTableKeys(nvimFiletypes);
  const arboristNames = [...arboristParsers.keys()].filter((name) => !nvimNames.has(name)).sort();
  const arboristRevisions = new Map(arboristNames.map((name) => {
    const parser = arboristParsers.get(name);
    return [name, arboristPins.get(name)?.revision ?? resolveRevision(name, parser)];
  }));
  const parserAdditions = arboristNames
    .map((name) => renderParser(name, arboristParsers.get(name), arboristRevisions.get(name)))
    .join("\n");
  const filetypeAdditions = arboristNames
    .filter((name) => !nvimFiletypeNames.has(name))
    .filter((name) => arboristFiletypes[name]?.length)
    .map((name) => `  [${JSON.stringify(name)}] = ${renderLuaValue(arboristFiletypes[name])},`)
    .join("\n");
  const header = [
    "-- Generated by scripts/update-vendor.mjs. Do not edit manually.",
    `-- nvim-treesitter revision: ${nvimRevision}`,
    `-- arborist revision: ${arboristRevision}`,
    "",
  ].join("\n");

  await writeFile(
    path.join(repoRoot, "lua", "tiny-treesitter", "parsers.lua"),
    `${header}${appendToReturnedTable(nvimParsers, `  -- Arborist parsers\n${parserAdditions}`)}`,
  );
  await writeFile(
    path.join(repoRoot, "plugin", "filetypes.lua"),
    `${header}${appendToFiletypes(nvimFiletypes, filetypeAdditions ? `  -- Arborist filetypes\n${filetypeAdditions}\n` : "")}`,
  );

  const targetQueries = path.join(repoRoot, "runtime", "queries");
  await rm(targetQueries, { recursive: true, force: true });
  await cp(nvimQueries, targetQueries, { recursive: true });

  const queryNames = new Set(arboristNames);

  for (const name of arboristNames) {
    for (const dependency of arboristParsers.get(name).requires ?? []) {
      queryNames.add(dependency);
    }
  }

  for (const name of [...queryNames].sort()) {
    const source = path.join(arboristDir, "queries", name);
    const target = path.join(targetQueries, name);

    if (!await exists(target) && await exists(source)) {
      await cp(source, target, { recursive: true });
    }
  }

  const currentSources = {
    "nvim-treesitter": {
      repository: repositories["nvim-treesitter"],
      revision: nvimRevision,
    },
    arborist: {
      repository: repositories.arborist,
      revision: arboristRevision,
    },
  };

  await writeFile(
    path.join(repoRoot, "vendor-sources.json"),
    `${JSON.stringify(currentSources, null, 2)}\n`,
  );
  await writeFile(
    path.join(repoRoot, ".vendor", "update-summary.md"),
    renderUpdateSummary(previousSources, currentSources),
  );

  await mkdir(path.join(repoRoot, "LICENSES"), { recursive: true });
  await writeFile(path.join(repoRoot, "LICENSES", "nvim-treesitter.txt"), nvimLicense);
  await writeFile(path.join(repoRoot, "LICENSES", "arborist.nvim.txt"), arboristLicense);

  console.log(`Updated vendor data from nvim-treesitter ${nvimRevision} and arborist.nvim ${arboristRevision}`);
}

await updateVendor();
