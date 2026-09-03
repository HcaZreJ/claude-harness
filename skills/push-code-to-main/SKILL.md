---
name: push-code-to-main
description: "Branch, commit, open a PR, squash-merge it to main, delete the remote and local branches (and, when the work was done in a git worktree, remove that worktree too), then sync local main. Use when the user says 'push code to main', '合代码到 main', '回合代码到 main', 'merge to main', 'ship this', 'open a PR and merge it', or otherwise asks to land the current work on main."
argument-hint: "[optional: short description of the change for the commit/PR]"
allowed-tools: Bash, Read, AskUserQuestion
---

# /push-code-to-main — Land current work on main

End-to-end: take the work done this session, put it on `main` through a PR, squash-merge
it, clean up the branches (and the worktree, when the work was done in one), then sync
local `main`.

This skill assumes pushing/merging is authorized — the user invoked it to do exactly that.

## Step 1 — Scope the files (commit-scope discipline)

Run `git status --short` and `git --no-pager diff --stat`.

Stage **only the files this session actually changed**. The working tree often holds
unrelated edits from other sessions or task lines. Build the explicit file list from the
work just completed and stage each path by name.

- Use `git add <path> <path> …` with explicit paths.
- Keep the staging surface to exactly the session's files; leave everything else unstaged.
- If it is unclear whether a modified file belongs to this work, ask the user with
  AskUserQuestion (list the ambiguous files) before staging.

After staging, run `git status --short` again and confirm the staged set (first column
`M`/`A`/`D`) is exactly the intended files, and unrelated files remain unstaged (` M`).

## Step 2 — Get onto a feature branch off up-to-date main

First detect where the work lives: `git rev-parse --show-toplevel` and
`git worktree list`. Handle the two cases separately.

**Case A — working in the primary checkout** (toplevel is the main repo root; branch is
`main` or a stale feature branch). `git fetch origin main` only moves the remote-tracking
ref; it does **not** update local `main`. Branching off a stale local `main` bases the work
on an old commit and breaks builds with "Module not found" for recently-merged code. So:

```bash
git checkout main && git pull origin main          # bring local main up to date
git checkout -b <type>/<slug> main                  # type ∈ fix|feat|chore|docs|test|devops
```

Pick a concise semantic branch slug from the change (e.g. `fix/stale-cache-key`).
Then re-stage the session's files on the new branch (Step 1's `git add <paths>`), because
the checkout carried the working-tree edits over but not the staging.

**Case B — working in a linked git worktree** (toplevel is a `.claude/worktrees/<name>`
path that `git worktree list` shows as a linked worktree; its branch is already a dedicated
`worktree-<slug>` branch). `main` is checked out by the primary worktree, so this checkout
stays on its own branch — commit the staged files **directly on the current branch**, no new
branch needed. Bring in recent main before pushing so the PR merges cleanly:

```bash
git fetch origin main                               # refresh remote-tracking ref
git rev-list --count HEAD..origin/main              # commits main is ahead (0 = fully up to date)
```

A merge PR reconciles the branch with main's newer commits at merge time; a non-zero count
is fine when the changed files don't overlap those commits. Note the worktree path and
branch name now — **Step 4 removes both after the merge**.

## Step 3 — Commit

Write a semantic branch commit `label(scope): summary` with a body that lists what
actually changed and why. This commit stays visible to reviewers on the PR page, and its
subject/body become your source text for the PR title/body in Step 4 — which is what
lands on `main` after squash-merge. So write it as if it were the final `main` commit,
not a WIP note.

Follow the repo's commit convention from its `CLAUDE.md` / `AGENTS.md`:

- Match the label set the repo uses (`fix`, `feat`, `chore`, `docs`, `test`, `devops`).
- Honor the repo's trailer rule. If the repo's instructions say to omit `Co-Authored-By`
  and "Generated with" trailers, omit them; otherwise add the trailer the harness specifies.
- Write the body in the language the repo's docs use.

```bash
git commit -m "$(cat <<'EOF'
<label>(<scope>): <summary>

- <what changed / why>
EOF
)"
```

## Step 4 — Push, PR, merge, clean up

Derive the GitHub repo from `git remote -v` (e.g. `owner/repo`).

```bash
git push -u origin <type>/<slug>

gh pr create --repo <owner/repo> --head <type>/<slug> --base main \
  --title "<label>(<scope>): <summary>" \
  --body "$(cat <<'EOF'
- <what changed / why — one bullet per meaningful edit>
EOF
)"

gh pr merge <PR#> --repo <owner/repo> --squash --delete-branch   # squash-merge; deletes the REMOTE branch
```

Then clean up locally, matching the case from Step 2:

**Case A — primary checkout:**
```bash
git checkout main && git pull origin main                        # sync local main to merge commit
git branch -D <type>/<slug>                                      # delete the LOCAL branch
git fetch --prune origin                                         # drop stale remote refs
```

**Case B — worktree** (work was done in a linked worktree → remove the worktree **and** its
branch). A branch checked out by a worktree can't be deleted, and you can't remove the
worktree you're standing in, so run this from the **primary** repo root:

```bash
cd "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"  # primary repo root
git pull origin main                                            # sync main to the merge commit
git worktree remove --force <worktree-path>                     # --force: worktree holds node_modules/.env.local/.next
git branch -D worktree-<slug>                                   # branch is now free to delete
git worktree prune && git fetch --prune origin                 # drop stale worktree + remote refs
```

Verify cleanup: `git branch` shows no leftover feature branch; `git branch -r | grep <slug>`
returns nothing; `git log --oneline -1 main` is the new merge commit. For Case B also confirm
`git worktree list` no longer lists the worktree and its directory is gone from disk.

Use `--squash` so each PR lands on `main` as a single commit — the PR title becomes the
`main` commit subject, keeping `main`'s history one-commit-per-change and readable. The
individual work-in-progress commits stay visible on the PR page for review.

## Step 5 — Confirm the merge commit's CI

If the repo runs a workflow on push to `main`, find that run and report its conclusion
before handing back. What a merge deploys, and how long it takes, is that repo's own
setup — read it from the workflow files instead of assuming it.

```bash
gh run list --repo <owner/repo> --branch main --limit 5        # find the run for the merge commit
gh run watch <run-id> --repo <owner/repo> --exit-status         # blocks until it finishes
```

Run the watch as a **background task**; you will be notified on completion, then report.
Do not poll in a tight loop.

When it finishes, report the run conclusion and, on failure, which job and step failed
plus the error (`gh run view <run-id> --json status,conclusion,jobs`). A repo that deploys
through a provider's own git integration rather than through Actions surfaces that state as
a commit status or a deployment instead:

```bash
gh api repos/<owner/repo>/commits/<sha>/status
gh api repos/<owner/repo>/deployments?sha=<sha>
```

## Notes

- Never stage with `git add -A` / `git add .` / `git commit -a` unless the user explicitly
  says "commit everything in the working tree".
- Run the repo's pre-commit checks only if its docs require them (some repos mandate a
  lint or build pass before commit; others say do not auto-build). Follow the repo's `CLAUDE.md`.
- If the merge has conflicts or the PR has required checks that block auto-merge, stop and
  report to the user rather than forcing it.
