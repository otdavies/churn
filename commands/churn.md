# /churn N - Iterative Refinement Loop

Run N iterations of focused subagent work with validation gates and drift correction.

## Usage
```
/churn 10           # Run 10 iterations (Work/Review alternation)
/churn 5 task       # Run 5 iterations on specific task
/churn 10 --linear  # All Work iterations (disable Review alternation)
/churn task         # Completion mode: run until DONE (max 50 safety limit)
```

## Completion Mode (N not specified)

When N is `?` or omitted, run until subagent returns "DONE" without "NEXT":
- Max 50 iterations (safety limit)
- Track as `N/?` where N increments
- Stop when subagent result contains "DONE" but not "NEXT"

## CRITICAL RULES

1. **YOU DO NOT TOUCH CODE** - Only subagents read/write files
2. **YOU PROVIDE CONTEXT, NOT TASKS** - Give subagents the plan path and state, let them choose work
3. **YOU VALIDATE AND GATE** - Run build/lint/test after each iteration, stop on failure
4. **YOU TRACK STATE** - Save iteration count, branch, validation results to working.md
5. **STOP ON FAILURE** - If build breaks or regression detected, stop and report

## Iteration Modes: Work → Review Cycle

Iterations alternate between **Work** and **Review** (corrective) modes:

### Work Iterations (odd: 1, 3, 5, ...)
Subagent reads the plan, assesses current state, and chooses the most important task to execute.

### Review Iterations (even: 2, 4, 6, ...) - THE CORRECTIVE FORCE
After each work iteration, a review iteration checks for **drift**:

1. **Plan drift**: Does the work align with docs/CHURN_PLAN.md? Update plan if needed.
2. **Doc drift**: Do docs/comments still match the code? Flag or fix.
3. **Test drift**: Are tests still passing? Do they cover the change?
4. **Scope drift**: Did the change introduce unrelated modifications?
5. **Goal drift**: Are we still moving toward the original objective?

Review output format:
- ALIGNED: [what's still on track]
- DRIFT: [what's drifted, with specific file:line]
- ACTION: [what to fix, or "none needed"]

The next Work iteration receives the full review (not truncated).

To run all iterations as Work mode (no Review alternation), use the `--linear` flag.

## Git Workflow

At churn start:
```bash
bash ~/.claude/memory-hooks/git.sh branch "churn-$(date +%s)"
```

Track branch name in state. Subagents commit their changes (see prompt template).

At churn end: meta review before reporting (see below).

## Build Detection

At churn start, detect project type and set BUILD_CMD:
```
- If `package.json` exists with "build" script: npm run build
- If `package.json` exists with "typecheck" script: npm run typecheck
- If `Cargo.toml` exists: cargo check
- If `go.mod` exists: go build ./...
- If `Makefile` exists: make check (or make build)
- If `pyproject.toml` or `setup.py` exists: python -m py_compile
- Otherwise: skip build validation
```

Store BUILD_CMD in state for validation steps.

## Plan Document

At churn start:
1. Create `docs/CHURN_PLAN.md` (create `/docs` folder if it doesn't exist)
2. Write initial plan:

```markdown
# Churn Plan

## GOAL
[user's objective from original request]

## REQUIREMENTS
[what must be true when done - success criteria]

## TASKS
- [ ] [task 1]
- [ ] [task 2]
- [ ] [task 3]

## DONE
[completed items moved here by subagents]

## NOTES
[observations, blockers, decisions recorded by subagents]
```

Subagents can:
- Read the plan to understand context
- Check off completed tasks (move to DONE)
- Add new tasks they discover
- Add notes about blockers or decisions

## The Loop

```
iteration = 1
while iteration <= N (or until DONE in completion mode):
    1. Save state: bash ~/.claude/memory-hooks/save.sh "churn: $iteration/$N | branch: X | build: Y | errors: Z"

    2. Spawn subagent with Task tool:
       - prompt: (see Work or Review template below)
       - model: haiku (fast/cheap) or sonnet for complex tasks
       - subagent_type: general-purpose

    3. Wait for return

    4. VALIDATE (before continuing):
       - Run BUILD_CMD, capture exit code and first 20 lines of output
       - If build fails: STOP loop, report to user with error output
       - Count lint errors if linter available
       - Run tests if test command detected
       - If errors increased from previous iteration: STOP (regression)
       - Save validation results to state

    5. iteration++

    6. In completion mode: check if result is "DONE" without "NEXT" → exit loop

    7. CONTINUE to next iteration
```

## Progress Tracking

Track metrics in state after each iteration:
- `errors_build`: count of build errors (0 = pass)
- `errors_lint`: count of lint warnings/errors
- `tests_pass`: count of passing tests
- `tests_fail`: count of failing tests

Convergence checks:
- If `errors_build > 0` for 2 iterations in a row: STOP (broken)
- If `errors_lint` increased 3 iterations in a row: WARN user
- If no metrics improved in 5 iterations: STOP (spinning)

## Rollback on Regression

If validation after iteration N shows regression (more errors than before):
1. Run: `git revert HEAD --no-edit`
2. Report: "Iteration N reverted - introduced regression: [what got worse]"
3. DO NOT decrement iteration count (we still used an iteration)
4. Continue - next subagent will see the reverted state and can try differently

## Subagent Prompt Template: Work Iteration

```
CHURN [N]/[TOTAL or ?] - WORK

GOAL: [overall objective from user's original request]

PLAN: ./docs/CHURN_PLAN.md (read this first)

STATE:
- Build: [pass/fail + first 3 errors if fail]
- Lint: [X errors, Y warnings]
- Tests: [X pass, Y fail]
- Last 3 iterations:
  - [N-1]: [one-line summary]
  - [N-2]: [one-line summary]
  - [N-3]: [one-line summary]

LAST REVIEW: [full review output from previous Review iteration, if any]

YOUR JOB:
1. Read docs/CHURN_PLAN.md
2. Assess current state (build/lint/test above)
3. Choose the MOST IMPORTANT thing to work on right now
4. Do ONE focused task
5. Update docs/CHURN_PLAN.md (check off task, add notes)
6. Commit: bash ~/.claude/memory-hooks/git.sh commit "churn [N]: [what you did]"
7. Return: "DONE: [what you did] | NEXT: [what's most important now]"

PRIORITY RULES:
- If build is broken, fix that first
- If tests fail, fix those before adding features
- Address DRIFT items from last review before new work
- Prioritize: broken > drift > incomplete > improvements

GO.
```

## Subagent Prompt Template: Review Iteration

```
CHURN [N]/[TOTAL or ?] - REVIEW

GOAL: [overall objective from user's original request]

PLAN: ./docs/CHURN_PLAN.md

LAST WORK: [full output from previous Work iteration]

STATE:
- Build: [pass/fail + errors]
- Lint: [X errors, Y warnings]
- Tests: [X pass, Y fail]
- Files changed in last commit: [git diff --name-only HEAD~1]

YOUR JOB:
Review the last Work iteration for drift:

1. **Plan drift**: Does the work align with docs/CHURN_PLAN.md goals?
2. **Doc drift**: Do docs/comments match the code changes?
3. **Test drift**: Are tests passing? Do they cover the change?
4. **Scope drift**: Did the change touch unrelated files?
5. **Goal drift**: Are we moving toward the objective?

If you find drift, you may fix small issues directly (update docs, add missing test).
If drift requires significant work, note it for the next Work iteration.

Update docs/CHURN_PLAN.md with observations.

If you made changes:
Commit: bash ~/.claude/memory-hooks/git.sh commit "churn [N]: review - [what you fixed]"

Return format:
ALIGNED: [what's on track]
DRIFT: [what's drifted, file:line if applicable]
ACTION: [what was fixed or what needs fixing]
DONE: Review complete | NEXT: [priority for next Work iteration]

GO.
```

## State Persistence

After EVERY iteration, save to working.md:
```bash
bash ~/.claude/memory-hooks/save.sh "churn: 4/10 | branch: churn-1705523400 | build: pass | errors: 0 | task: refactor auth | last: fixed login.ts"
```

State format: `churn: N/TOTAL | branch: X | build: Y | errors: Z | task: T | last: L`

If session resumes after compaction, working.md tells you where to continue.

## Example Flow

User: `/churn 6 refactor the auth module`

```
1. Create branch churn-TIMESTAMP
2. Create docs/CHURN_PLAN.md with goal and initial tasks
3. Detect BUILD_CMD (npm run build)
4. Iteration 1 (Work): Subagent reads plan, chooses task, executes, commits
5. Validate: run build, check pass/fail
6. Iteration 2 (Review): Check for drift, fix docs, note issues
7. Validate: run build
8. Iteration 3 (Work): Address drift items, continue with plan
9. Validate...
... continue to iteration 6
10. Meta review
11. Report to user
```

## When N is Reached (or DONE in completion mode)

Only after final iteration completes:

### Meta Review
Run git log to see all churn commits, then spawn one final subagent:
```
META REVIEW

GOAL: [original objective]

BRANCH: [branch name]
COMMITS:
[git log --oneline output]

FINAL STATE:
- Build: [pass/fail]
- Tests: [X pass, Y fail]
- docs/CHURN_PLAN.md status: [read and summarize]

YOUR JOB:
1. Read docs/CHURN_PLAN.md
2. Read key changed files
3. Assess: was the goal achieved?
4. List: what was accomplished, what remains incomplete
5. Note: any risks or issues to address

Return: "REVIEW: [comprehensive summary]"

GO.
```

### Report to User
1. Show meta review summary
2. Show final validation state (build/tests)
3. List commits made
4. Show docs/CHURN_PLAN.md status (what's done vs remaining)
5. Suggest: merge branch, continue work, or discard
6. Exit churn mode
