# /churn N - Iterative Refinement Loop

Run N iterations of focused subagent work. You are the loop controller, nothing more.

## Usage
```
/churn 10       # Run 10 iterations (default: alternating critique/fix)
/churn 5 task   # Run 5 iterations on specific task
/churn 10 --linear  # Same-type iterations (disable alternation)
/churn task     # Completion mode: run until DONE (max 50 safety limit)
```

## Completion Mode (N not specified)

When N is `?` or omitted, run until subagent returns "DONE" without "NEXT":
- Max 50 iterations (safety limit)
- Track as `N/?` where N increments
- Stop when subagent result contains "DONE" but not "NEXT"

## Default Behavior: Critique/Fix Alternation

By default, iterations alternate between critique and fix modes:
- **Odd iterations** (1, 3, 5, ...): Critique mode
- **Even iterations** (2, 4, 6, ...): Fix mode

To run all iterations as the same type, use the `--linear` flag.

## CRITICAL RULES

1. **YOU DO NOT TOUCH FILES** - Only subagents read/write files
2. **YOU ONLY COUNT AND DISPATCH** - Your job is: spawn → wait → increment → repeat
3. **KEEP GOING UNTIL N** - Even if you think work is "done", keep spawning until iteration N
4. **MINIMUM CONTEXT TO SUBAGENTS** - Only what they absolutely need, nothing more
5. **SURVIVE COMPACTION** - Save iteration count to working.md after each step

## Git Workflow

At churn start:
```bash
bash ~/.claude/commands/git.sh branch "churn-$(date +%s)"
```

Track branch name in state. Subagents commit their changes (see prompt template).

At churn end: meta review before reporting (see below).

## The Loop

```
iteration = 1
while iteration <= N (or until DONE in completion mode):
    1. Save state: bash ~/.claude/memory-hooks/save.sh "churn: $iteration/$N | branch: X | task: Y | last: Z"
    2. Spawn subagent with Task tool:
       - prompt: (see template below - includes git commit instruction)
       - model: haiku (fast/cheap)
       - subagent_type: Explore or general-purpose
    3. Wait for return
    4. iteration++
    5. In completion mode: check if result is "DONE" without "NEXT" → exit loop
    6. CONTINUE - do not stop, do not evaluate, just spawn next
```

## Subagent Prompt Template

```
CHURN [N]/[TOTAL or ?]

TASK: [one sentence - what to do this iteration]

CONTEXT:
[absolute minimum - 2-3 lines max]

PREV: [last iteration's DONE result, if available - truncate to 50 words if longer]

RULES:
- Do ONE thing
- Be concise
- After changes: bash ~/.claude/commands/git.sh commit "churn [N]: [what you did]"
- Return: "DONE: [1 sentence result]" or "NEXT: [what's needed]"

GO.
```

## State Persistence

After EVERY iteration, save to working.md:
```bash
bash ~/.claude/memory-hooks/save.sh "churn: 4/10 | branch: churn-1705523400 | task: refactor auth | last: fixed login.ts"
```

State format: `churn: N/? | branch: X | task: Y | last: Z`

If session resumes after compaction, working.md tells you where to continue.

## Example Flow

User: `/churn 5 refactor the auth module`

You count 1→2→3→4→5, spawning a fresh subagent each time. That's it. Each iteration is a Task tool call with one specific step.

## When N is Reached (or DONE in completion mode)

Only after final iteration completes:

### Meta Review
Run git log to see all churn commits, then spawn one final subagent:
```
META REVIEW

TASK: Review the churn session changes and provide summary.

CONTEXT:
- Branch: [branch name]
- Commits: [git log --oneline output]

RULES:
- Read changed files
- Summarize what was accomplished
- Note any issues or incomplete work
- Return: "REVIEW: [summary]"

GO.
```

### Report to User
1. Show meta review summary
2. List commits made
3. Suggest: merge branch, continue work, or discard
4. Exit churn mode
