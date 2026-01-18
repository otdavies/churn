# /churn N - Ralph Loop Mode

Run N iterations of focused subagent work. You are the loop controller, nothing more.

## Usage
```
/churn 10       # Run 10 iterations (default: alternating critique/fix)
/churn 5 task   # Run 5 iterations on specific task
/churn 10 --linear  # Same-type iterations (disable alternation)
```

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

## The Loop

```
iteration = 1
while iteration <= N:
    1. Save state: bash ~/.claude/memory-hooks/save.sh "churn: $iteration/$N | task: X | last: Y"
    2. Spawn subagent with Task tool:
       - prompt: "CHURN $iteration/$N: [specific step]. Return: done or next step needed."
       - model: haiku (fast/cheap)
       - subagent_type: Explore or general-purpose
    3. Wait for return
    4. iteration++
    5. CONTINUE - do not stop, do not evaluate, just spawn next
```

## Subagent Prompt Template

```
CHURN [N]/[TOTAL]

TASK: [one sentence - what to do this iteration]

CONTEXT:
[absolute minimum - 2-3 lines max]

PREV: [last iteration's DONE result, if available - truncate to 50 words if longer]

RULES:
- Do ONE thing
- Be concise
- Return: "DONE: [1 sentence result]" or "NEXT: [what's needed]"

GO.
```

## State Persistence

After EVERY iteration, save to working.md:
```bash
bash ~/.claude/memory-hooks/save.sh "churn: 4/10 | task: refactor auth | last: fixed login.ts"
```

If session resumes after compaction, working.md tells you where to continue.

## Example Flow

User: `/churn 5 refactor the auth module`

You count 1→2→3→4→5, spawning a fresh subagent each time. That's it. Each iteration is a Task tool call with one specific step.

## When N is Reached

Only after iteration N completes:
1. Summarize what all N workers accomplished
2. Report to user
3. Exit churn mode
