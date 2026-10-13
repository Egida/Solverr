---
name: debug-fix
description: Find and fix a bug in Solverr. Reproduces it first, proves a hypothesis before changing code, fixes it where the bad state originates, pins it with a test seen failing with the fix reverted, then sweeps for sibling sites (the other engine first) and records them in the commit body. Add `--fast` for an urgent fix on a `hotfix/*` branch with a minimal change and a pull request; it still never pushes `main` and never merges.
argument-hint: "<issue, error, or description> [--fast] (e.g. 'stealth returns cookies from before waitInSeconds', 'unseensnick/Solverr#12 --fast')"
disable-model-invocation: true
allowed-tools:
  - Bash(git *)
  - Bash(gh *)
  - Bash(uv run *)
  - Bash(PYTHONPATH=src uv run *)
  - Read
  - Glob
  - Grep
  - Edit
  - Write
---

Find and fix the issue described by `$ARGUMENTS`.

## Mode

Check `$ARGUMENTS` for `--fast` and strip it before parsing the problem.

- **Default**: the careful path. Use it whenever there is time to do this right.
- **`--fast`**: an urgent fix for a broken release. It skips the reproduction and the deep investigation, keeps the change minimal, and ships a pull request from a `hotfix/*` branch. Before committing to it, confirm with the owner that the fix is genuinely urgent; if not, suggest dropping `--fast`.

Neither mode pushes `main` or merges. The guard in `.claude/hooks/block-dangerous-commands.sh` blocks both, and merging is always the owner's call.

## Step 1: Understand

- An issue reference: `gh issue view <N> --repo unseensnick/Solverr`.
- An error or traceback: read it for the file, line, error type and call chain. `docker logs solverr` with `LOG_LEVEL=debug` carries the engine's own view of the page.
- A description: pin down expected against actual, which engine (`chrome`, `stealth`, or the fallback between them), and which surface (`/v1` or the passthrough).

If any of that is unclear, ask before going further.

## Step 2: Hotfix branch (`--fast` only)

Create `hotfix/<short-description>` from `main`, after asking the owner to confirm the name. Keep the name generic: no site names (`workflow.md`, "Public-facing naming"). If the tree is dirty, ask what to do with the uncommitted work rather than stashing it silently. In default mode, skip this; the branch comes in Step 7.

## Step 3: Reproduce (default only)

Find the cheapest trigger that fails on demand, in this order of preference:

1. **A browser-free test.** A new case in the matching `src/test_*.py` module. When the bug is a rule both engines must follow, the reproducer is one case in `src/test_engine_conformance.py`, driven through `src/engine_fakes.py`, so it runs against both engines at once.
2. **A request against a running Solverr** (`curl` to `/v1`) when the bug needs the real server but not a live challenge.
3. **A live challenge.** When only a real Cloudflare page shows the bug, the reproducer is `/live-check`, which only the owner can invoke. Stop and hand the owner a paste-ready line, for example `/live-check the cookie read after waitInSeconds on stealth`, then carry on from its result.

If it will not reproduce: check the environment (env vars, `PROXY_URL`, image tag against the source), whether it is a race (shared state across waitress threads, the single stealth loop in `src/async_runtime.py`), and whether it is already fixed (`git log --oneline -20 -- <file>`).

## Step 4: Investigate (default only)

Do not skip ahead to guessing.

1. Locate the symptom: the file and line that produce the wrong output.
2. Read the path backwards: what called it, with what data. Requests cross the controller (`src/flaresolverr_service.py`), the spine (`assembly.py`, `pipeline.py`, `budget.py`, `sessions.py`) and an engine adapter in `src/engines/`.
3. Read the history: `git log --oneline -20 -- <file>`, `git log --all --grep="<keyword>"`. Check `docs/dev/upstream-sync.md` before calling a difference from an upstream a bug; it may be deliberate.
4. Form a hypothesis: "X is wrong because Y."
5. Prove it with a targeted assertion or debug log before changing anything.
6. If it is wrong, trace a different path rather than retrying the same guess.

Code that looks wrong here often encodes a measured constraint (`.claude/rules/architecture.md`). Ask for a measurement before "fixing" one of those.

## Step 5: Fix

- Fix it where the bad state originates, not where it shows up. No defensive check that hides the symptom.
- Make the smallest correct change. If the correct fix needs a helper extracted or a signature changed, do that (`code-quality.md`), but leave unrelated code alone.
- Before writing a helper, run the reuse search from the DRY rule in `code-quality.md` (name stem, arguments and return type, the rule it encodes) and say what you reused or what you searched.
- **Write once, both engines get it.** A fix to behaviour a client can observe lands for Chrome and stealth in the same commit, per `.claude/rules/engine-layer.md`. A defect in the spine is already a defect for both. The only exit is a named browser-automation mechanism one engine cannot provide, cited in the commit and recorded in the ledger.

With `--fast`: if the fix needs more than about 50 changed lines, warn the owner that it may not be a hotfix. No formatting changes, no unrelated cleanup.

## Step 6: Verify

**Both modes: sweep for siblings.** Search for the same defect elsewhere: the other engine first (its adapter and its clearing core), then the same call pattern across `src/`. List each site as fixed or left, with the reason. The reported case passing is not the bug being fixed.

**Default:**

- The reproducing test from Step 3 now passes.
- **Revert the fix and watch the test fail**, then restore it (engine-layer.md, "Verify by mutation"). A test that passes either way proves nothing.
- Run the touched module: `PYTHONPATH=src uv run --no-project python -m unittest <module>`.
- Run the whole browser-free suite: `PYTHONPATH=src uv run --no-project python -m unittest discover -s src -p 'test_*.py' -t src`. Never a hand-picked list as the final check; it skips the conformance suite.
- If the fix touches detection or an engine, the unit tests cannot say whether a page still clears. Hand the owner a paste-ready `/live-check` line naming the change.

**`--fast`:**

- Run the touched module and the whole browser-free suite (it takes seconds).
- If the original error can be reproduced, confirm it is gone.
- Ask the owner whether they want a `/live-check` before shipping.

## Step 7: Commit and ship

The commit body ends with a `Siblings:` line listing the sweep from Step 6, or `Siblings: none found (searched: <terms>)`.

**Default:**

- Create a branch if still on `main` (`fix/<short-description>`).
- Stage only the fix and its test.
- Commit as `fix(scope): <what was wrong>` (scope `chrome`, `stealth`, `sessions`, or the module), following the pre-commit checklist in `workflow.md`: no em dash, no AI watermark, no site names, issues as `unseensnick/Solverr#N`, never a bare `#N`.
- Add a `## [Unreleased]` CHANGELOG entry under `Fixes` if someone running Solverr could notice the bug, with the bold headline carrying everything a deployer must know.
- Stop there. Pushing and the pull request are `/ship`.

**`--fast`:**

- Stage only the fix files. Draft the commit as above (`hotfix` is not a conventional type, so it is `fix`) and ask the owner to confirm it.
- Ask before pushing, then `git push -u origin hotfix/<description>`. Never `main`, never a force push.
- Draft the pull request against `main`: title `[HOTFIX] <description>`, body following `.github/pull_request_template.md` with what broke, why, and what fixes it. No AI attribution. Ask the owner to confirm, then `gh pr create --repo unseensnick/Solverr --base main`.
- Show the pull request URL and stop. The owner merges it.

## Rules

- Never skip a confirmation in `--fast` mode: branch name, commit message, push, pull request.
- Never push `main`, never force push, never merge a pull request, never `--no-verify`.
- Never commit secrets or unrelated changes.
- If the owner says "skip" at a step, skip it and move on.
- If a `--fast` fix turns out to be complicated, say so and suggest the default path.
