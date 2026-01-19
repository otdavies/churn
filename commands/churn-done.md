# /churn-done - Finalize Churn Branch

Squash commits, rename branch, prepare for merge/push.

## When to Use

After completing a `/churn` session when you want to:
- Squash all churn commits into a single clean commit
- Rename the branch from `churn/...` to a semantic name
- Prepare for push or merge

## Prerequisites

- On a `churn/*` branch
- Working tree is clean (all changes committed)
- Churn work is complete (or you want to stop here)

## Process

### 1. Validate State

First, check you're on a churn branch with clean state:

```bash
BRANCH=$(git branch --show-current)
if [[ "$BRANCH" != churn/* ]]; then
    echo "Not on a churn branch. Current: $BRANCH"
    # Offer to switch if churn branch exists
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Uncommitted changes detected. Commit or stash first."
fi
```

### 2. Find Base Commit

```bash
BASE=$(bash ~/.claude/memory-hooks/git.sh churn-base)
echo "Base commit: $BASE"
```

### 3. List Commits to Squash

```bash
COMMITS=$(bash ~/.claude/memory-hooks/git.sh churn-commits)
COMMIT_COUNT=$(echo "$COMMITS" | wc -l | tr -d ' ')
echo "Commits to squash: $COMMIT_COUNT"
echo "$COMMITS"
```

### 4. Generate Commit Message

Analyze the commits and generate a clean commit message:

**Format:**
```
[Type]: Brief description (50 chars max)

- Key change 1
- Key change 2
- Key change 3

[Churn: N iterations, YYYY-MM-DD]
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `refactor` - Code restructuring
- `docs` - Documentation
- `test` - Tests
- `chore` - Maintenance

### 5. Present to User

```
FINALIZE CHURN BRANCH

Branch: churn/implement-auth-0119-1430
Commits to squash: 12
Base: abc1234

Suggested commit message:
---
feat: Implement JWT authentication with refresh tokens

- Add token generation and validation in src/auth.ts
- Implement refresh token rotation
- Add auth middleware for protected routes
- Add comprehensive test coverage

[Churn: 10 iterations, 2026-01-19]
---

Suggested branch name: feature/jwt-auth

Options:
1. Accept and finalize
2. Edit commit message
3. Different branch name
4. Cancel
```

Use `AskUserQuestion` to get user choice.

### 6. Execute Finalization

On confirmation:

```bash
# Squash commits
bash ~/.claude/memory-hooks/git.sh finalize "$BASE" "$COMMIT_MESSAGE"

# Rename branch
bash ~/.claude/memory-hooks/git.sh rename-branch "$NEW_BRANCH_NAME"
```

### 7. Update State

Save to working.md:
```
churn-state: finalized
churn-final-branch: feature/jwt-auth
churn-final-commit: [new-hash]
churn-recovery: [old-hash]
```

### 8. Report Success

```
Branch finalized!

Before: churn/implement-auth-0119-1430 (12 commits)
After:  feature/jwt-auth (1 commit)

Next steps:
- /churn-push  - Push to remote and optionally create PR
- git push -u origin feature/jwt-auth  - Push manually
- git checkout main && git merge feature/jwt-auth  - Merge locally

Recovery available: git reset --hard [recovery-hash]
```

## Error Handling

**Uncommitted changes:**
```
Cannot finalize: uncommitted changes detected.
Run: git stash, then /churn-done
Or: git add -A && git commit -m "WIP" first
```

**Not on churn branch:**
```
Cannot finalize: not on a churn/* branch.
Current branch: main
If you have a churn branch to finalize: git checkout churn/[branch-name]
```

**Squash fails:**
```
Squash failed. Recovery point saved.
Run: bash ~/.claude/memory-hooks/git.sh abort-finalize
To restore your previous state.
```

## Branch Naming Suggestions

Based on commit analysis:
- `feature/` - New functionality
- `fix/` - Bug fixes
- `refactor/` - Code improvements
- `docs/` - Documentation changes
- `test/` - Test additions/fixes

Generate name from:
1. The original /churn task description
2. The CHURN_PLAN.md goal (if exists)
3. The commit message patterns

## Important Notes

- This is a **destructive operation** (squashes history) but recovery is available
- Recovery point stored until next /churn-done or session end
- The original commits are still in git reflog for 90 days
- Always review the suggested commit message before accepting
