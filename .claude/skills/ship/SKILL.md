---
name: ship
description: Commit the current changes, push the feature branch, and open a pull request, confirming with the owner before each step. Runs the code-reviewer agent on the staged diff before drafting the message, and holds the message and the pull request to Solverr's commit, CHANGELOG and naming rules. Never pushes main and never merges.
argument-hint: "[optional commit subject or pull request title]"
disable-model-invocation: true
allowed-tools:
  - Bash(git status)
  - Bash(git diff *)
  - Bash(git log *)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git push *)
  - Bash(git checkout *)
  - Bash(git branch *)
  - Bash(gh pr create *)
  - Bash(gh pr view *)
  - Agent
---

Ship the current changes: commit, push, pull request. Ask the owner with `AskUserQuestion` before each step. If `$ARGUMENTS` is given, use it as the commit subject or pull request title.

## Step 1: Scan

- `git status`, `git diff` (staged and unstaged), `git log --oneline -5`.
- Summarize for the owner: modified, added, deleted and untracked files.
- If there are no changes, say so and stop.
- If the current branch is `main`, propose a feature branch (`fix/`, `feat/`, `docs/`, `chore/`, named without site names) and create it once confirmed. Nothing is ever pushed to `main`.

## Step 2: Stage and commit

- Propose the files to stage. Never stage secrets (`.env*`, `*.pem`, `*.key`, credentials), `Handoff.md` (gitignored), `.venv/`, `__pycache__/`, or editor and OS files.
- Run the `code-reviewer` agent on the staged diff (`git diff --cached`) before drafting the message, and show its findings with the proposal. Fix or explicitly defer each one before committing.
- If the change is something a person running Solverr could notice, check that `CHANGELOG.md` has a `## [Unreleased]` entry: a bold, self-contained headline ending in `.`, `!` or `?`, with any new setting or default inside the bold text, because `release.yml` keeps only the headline. A change with no visible effect gets a plain line under `Other`; contributor tooling (`.claude/`, hooks, CI, tests) gets none. Rules: `workflow.md`, "CHANGELOG".
- If behaviour or config changed, check that the matching user guide in `README.md` or `docs/` changed with it.
- Draft the message against the pre-commit checklist in `.claude/rules/workflow.md`:
  1. Subject `type(scope): summary`, imperative, lower-case, no trailing period, at most 72 characters.
  2. No em dash anywhere.
  3. No AI watermark: no AI `Co-authored-by` trailer, no "Generated with" footer.
  4. No bare `#N`. Use `owner/repo#N` (`unseensnick/Solverr#12`, `FlareSolverr/FlareSolverr#1626`).
  5. No site names or scraping vocabulary.
  6. A non-trivial change has a body that leads with one or two plain sentences, then benefit-first bullets.
- Ask the owner to confirm or edit the exact files and message. Only then stage and commit.
- If a hook rejects the commit, fix the cause and make a new commit. Never `--no-verify`, never amend to get past it.

## Step 3: Push

- Check whether the branch has an upstream. If not, propose `git push -u origin <branch>`.
- Ask the owner to confirm, then push. Never `main`, never a force push. The guard in `.claude/hooks/block-dangerous-commands.sh` refuses both.

## Step 4: Pull request

- `gh pr view --repo unseensnick/Solverr`: if a pull request already exists for the branch, show its URL and stop.
- Read every commit on the branch against `main`, not only the last one.
- Draft a title (at most 72 characters, same naming rules as the commit) and a body that fills `.github/pull_request_template.md`: `## Summary` (what and why, issues as `owner/repo#N`), `## How it was tested` (the browser-free suite result, and any `/live-check` run if the change touches solving), and `## Checklist` with each item ticked only when it is true.
- No AI attribution footer.
- Ask the owner to confirm or edit, then:

  ```
  gh pr create --repo unseensnick/Solverr --base main --title "..." --body "..."
  ```

- Show the pull request URL and stop. Merging is the owner's, always with a merge commit (`workflow.md`, "Merging a pull request").

## Rules

- Never skip a confirmation. Each step needs the owner's explicit yes.
- Never push `main`, never force push, never merge, never `--no-verify`.
- Never commit secrets or credential files.
- If the owner says "skip" at a step, skip it and move on.
