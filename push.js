const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const repoRoot = process.cwd();
const cdnDir = path.join(repoRoot, "cdn");
const deployDir = path.join(repoRoot, ".deploy-pages");

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: options.cwd || repoRoot,
    stdio: options.capture ? ["ignore", "pipe", "pipe"] : "inherit",
    encoding: "utf8",
    shell: false,
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    const output = options.capture ? `${result.stdout || ""}${result.stderr || ""}` : "";
    throw new Error(`Command failed: ${command} ${args.join(" ")}${output ? `\n${output}` : ""}`);
  }

  return options.capture ? (result.stdout || "").trim() : "";
}

function getOriginRepoSlug() {
  const remote = run("git", ["remote", "get-url", "origin"], { capture: true });
  const match = remote.match(/github\.com[:/](.+?)\.git$/i) || remote.match(/github\.com[:/](.+?)$/i);
  if (!match) {
    throw new Error(`Could not parse GitHub repo from origin remote: ${remote}`);
  }
  return match[1];
}

function getPagesUrl(repoSlug) {
  const parts = repoSlug.split("/");
  if (parts.length !== 2) {
    throw new Error(`Unexpected repo slug: ${repoSlug}`);
  }
  const owner = parts[0];
  const repo = parts[1];
  return `https://${owner}.github.io/${repo}/`;
}

function hasChanges() {
  return run("git", ["status", "--porcelain"], { capture: true }).length > 0;
}

function pushCurrentBranch(commitMessage) {
  if (!hasChanges()) {
    console.log("No source changes to commit on the current branch.");
    return;
  }

  run("git", ["add", "-A"]);
  run("git", ["commit", "-m", commitMessage]);
  run("git", ["push", "origin", "HEAD"]);
}

function recreateDeployWorktree() {
  const worktreeList = run("git", ["worktree", "list", "--porcelain"], { capture: true });
  if (worktreeList.includes(`worktree ${deployDir}`)) {
    run("git", ["worktree", "remove", "--force", deployDir]);
  } else if (fs.existsSync(deployDir)) {
    fs.rmSync(deployDir, { recursive: true, force: true });
  }

  run("git", ["worktree", "add", "--force", "-B", "gh-pages", deployDir, "HEAD"]);
}

function copyCdnBundle() {
  if (!fs.existsSync(cdnDir)) {
    throw new Error(`Missing CDN folder: ${cdnDir}`);
  }

  fs.cpSync(cdnDir, deployDir, { recursive: true, force: true });
}

function pushPagesBranch() {
  run("git", ["add", "-A"], { cwd: deployDir });

  if (run("git", ["status", "--porcelain"], { cwd: deployDir, capture: true }).length > 0) {
    run("git", ["commit", "-m", "Update CDN bundle"], { cwd: deployDir });
  } else {
    console.log("No CDN changes to commit.");
  }

  run("git", ["push", "origin", "gh-pages"], { cwd: deployDir });
}

function main() {
  const argMessageIndex = process.argv.findIndex((value) => value === "-m" || value === "--message");
  const commitMessage = argMessageIndex >= 0 && process.argv[argMessageIndex + 1]
    ? process.argv[argMessageIndex + 1]
    : "Update project assets";

  const repoSlug = getOriginRepoSlug();
  const pagesUrl = getPagesUrl(repoSlug);

  console.log("Committing and pushing source branch...");
  pushCurrentBranch(commitMessage);

  console.log("Publishing CDN bundle to gh-pages...");
  recreateDeployWorktree();
  copyCdnBundle();
  pushPagesBranch();

  console.log("");
  console.log(`Pages URL: ${pagesUrl}`);
  console.log(`Godot base URL: ${pagesUrl}godot/`);
  console.log("");
  console.log("If GitHub Pages is not enabled yet, turn it on once in repository settings:");
  console.log("Settings > Pages > Deploy from a branch > gh-pages / root");
}

main();
