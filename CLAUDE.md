# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Standards reference**: <https://github.com/vergil-project/vergil-tooling>
— active standards documentation lives in the vergil-tooling repository under `docs/`.
Repository profile: `vergil.toml`.

## Memory management

Memory is allowed with human approval. The authoritative policy is in
the user's global `~/.claude/CLAUDE.md` — agents must propose memory
writes and suggest a destination (repo memory, global CLAUDE.md, or
plugin/skill issue) before writing. See that file for the full
workflow.

Available skills:
- `/vergil:memory-init` — set up or update the policy header
  in a project's `MEMORY.md`.
- `/vergil:memory-audit` — structured collaborative review
  of memory files.

## Parallel AI agent development

This repository supports running multiple Claude Code agents in parallel via
git worktrees. The convention keeps parallel agents' working trees isolated
while preserving shared project memory (which Claude Code derives from the
session's starting CWD).

**Canonical spec:**
[`vergil-tooling/docs/specs/worktree-convention.md`](https://github.com/vergil-project/vergil-tooling/blob/develop/docs/specs/worktree-convention.md)
— full rationale, trust model, failure modes, and memory-path implications.
The canonical text lives in `vergil-tooling`; this section is the local
on-ramp.

### Structure

```text
<project-root>/                              ← sessions ALWAYS start here
  .git/
  CLAUDE.md, …                               ← main worktree (usually `develop`)
  .worktrees/                                ← container for parallel worktrees
    issue-<N>-<short-slug>/                  ← worktree on feature/<N>-<short-slug>
    …
```

### Rules

1. **Sessions always start at the project root.**
   Never start Claude from inside `.worktrees/<name>/`. This keeps the
   memory-path slug stable and shared.
2. **Each parallel agent is assigned exactly one worktree.** The session
   prompt names the worktree (see Agent prompt contract below).
   - For Read / Edit / Write tools: use the worktree's absolute path.
   - For Bash commands that touch files: `cd` into the worktree first,
     or use absolute paths.
3. **The main worktree is read-only.** All edits flow through a worktree
   on a feature branch — the logical endpoint of the standing
   "no direct commits to develop" policy.
4. **One worktree per issue.** Don't stack in-flight issues. When a
   branch lands, remove the worktree before starting the next.
5. **Naming: `issue-<N>-<short-slug>`.** `<N>` is the GitHub issue
   number; `<short-slug>` is 2–4 kebab-case tokens.

### Agent prompt contract

When launching a parallel-agent session, use this template (fill in the
placeholders):

```text
You are working on issue #<N>: <issue title>.

Your worktree is: <project-root>/.worktrees/issue-<N>-<slug>/
Your branch is:   feature/<N>-<slug>

Rules for this session:
- Do all git operations from inside your worktree:
    cd <absolute-worktree-path> && vrg-git <command>
- For Read / Edit / Write tools, use the absolute worktree path.
- For Bash commands that touch files, cd into the worktree first
  or use absolute paths.
- Do not edit files at the project root. The main worktree is
  read-only — all changes flow through your worktree on your
  feature branch.
- When you need to run validation, run it from inside your worktree
  (vrg-container-run mounts the current directory).
```

All fields are required.

## Shell command policy

Use `vrg-git` instead of `git` for all git operations. Use `vrg-gh`
instead of `gh` for all GitHub CLI operations. These wrappers enforce
subcommand allowlists, flag deny lists, and credential selection.

Raw `git` and `gh` are denied by the permission model. If a command
is not available through the wrappers, explain the situation to the
human who can run it directly via `! <command>` in the prompt.

## Validation

```bash
vrg-container-run -- vrg-validate
```

This is the **only** validation command. Do not run individual linters,
formatters, or other tools outside of `vrg-validate`. If a tool is not
invoked by `vrg-validate`, it is not part of the validation pipeline.

## Project Overview

`mq-rest-admin` is a Ruby wrapper for the IBM MQ administrative REST
API. The project provides typed Ruby methods for every MQSC command
exposed by the `runCommandJSON` REST endpoint, with automatic attribute name
translation between Ruby idioms and native MQSC parameter names.

**Project name**: mq-rest-admin-ruby

**Status**: Pre-alpha (initial setup)

**Canonical Standards**: This repository follows standards at <https://github.com/vergil-project/vergil-tooling> (local path: `../vergil-tooling` if available)

## Development Commands

### Standard Tooling

The Claude Code PreToolUse hook guard (`.claude/hooks/guard.sh`)
blocks raw `git` and `gh` commands — use `vrg-git` / `vrg-gh`
wrappers.

### Environment Setup

```bash
bundle install
```

### Validation

```bash
vrg-container-run -- vrg-validate   # Canonical validation (runs in dev container)
```

### CI

PR CI (`.github/workflows/ci.yml`) uses vergil-actions v2.0 reusable
workflows for quality (lint, typecheck), unit tests (Ruby 3.2/3.3/3.4
matrix), security (CodeQL, Trivy, Semgrep, standards), and release gates.
Bespoke jobs handle dependency audit (license_finder with repo-specific
decisions file) and integration tests (MQ containers).

### Local MQ Container

The MQ development environment is owned by the
[mq-rest-admin-dev-environment](https://github.com/mq-rest-admin-project/mq-rest-admin-dev-environment)
repository. Clone it as a sibling directory before running lifecycle
scripts:

```bash
# Prerequisite (one-time)
git clone https://github.com/mq-rest-admin-project/mq-rest-admin-dev-environment.git ../mq-rest-admin-dev-environment

# Start the containerized MQ queue managers
./scripts/dev/mq_start.sh

# Seed deterministic test objects (DEV.* prefix)
./scripts/dev/mq_seed.sh

# Verify REST-based MQSC responses
./scripts/dev/mq_verify.sh

# Stop the queue managers
./scripts/dev/mq_stop.sh

# Reset to clean state (removes data volumes)
./scripts/dev/mq_reset.sh
```

Container details:

- Queue managers: `QM1` and `QM2`
- QM1 ports: `1444` (MQ listener), `9473` (mqweb console + REST API)
- QM2 ports: `1445` (MQ listener), `9474` (mqweb console + REST API)
- Admin credentials: `mqadmin` / `mqadmin`
- Read-only credentials: `mqreader` / `mqreader`
- QM1 REST base URL: `https://localhost:9473/ibmmq/rest/v2`
- QM2 REST base URL: `https://localhost:9474/ibmmq/rest/v2`
- Object prefix: `DEV.*`

## Architecture

### Gem layout (`lib/mq/rest/admin/`)

- **`version.rb`** — `MQ::REST::Admin::VERSION`
- **`errors.rb`** — `Error < StandardError` + 6 subclasses
- **`auth.rb`** — `BasicAuth`, `LTPAAuth`, `CertificateAuth` (`Data.define`)
- **`transport.rb`** — `TransportResponse` (`Data.define`), `NetHTTPTransport`
- **`mapping_data.rb`** — Loads and freezes `mapping-data.json`
- **`mapping.rb`** — 3-layer mapping pipeline + `MappingIssue`
- **`mapping_merge.rb`** — Override validation and merge/replace
- **`session.rb`** — `Session` class, `mqsc_command` dispatcher
- **`commands.rb`** — 149 MQSC command methods (module)
- **`ensure.rb`** — 16 idempotent ensure methods (module)
- **`sync.rb`** — 9 synchronous polling methods (module)

### Key design decisions

- **Zero runtime dependencies** — uses `net/http` from stdlib
- **Ruby 3.2+** — uses `Data.define` for immutable value objects
- **Module mixins** — `Commands`, `Ensure`, `Sync` included into `Session`

## Key References

**Reference implementation**: `../mq-rest-admin-python` (Python version)

**External Documentation**:

- IBM MQ 9.4 administrative REST API
- MQSC command reference
