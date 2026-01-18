#!/bin/bash
# Gentler Memory - Session Start Hook
# Injects self-model + sticky memory into context at session start

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
MEMORY_DIR="$CLAUDE_DIR/memory"

# Read input JSON from stdin
INPUT=$(cat)

# Extract cwd from input
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SOURCE=$(echo "$INPUT" | jq -r '.source // "startup"')

# Only inject on fresh startup, not on resume/compact
if [[ "$SOURCE" != "startup" ]]; then
    echo '{"continue": true}'
    exit 0
fi

# Encode project path for directory name (same as Claude Code does)
if [[ -n "$CWD" ]]; then
    PROJECT_ENCODED=$(echo "$CWD" | sed 's|/|-|g')
    PROJECT_MEMORY_DIR="$CLAUDE_DIR/projects/$PROJECT_ENCODED/memory"
else
    PROJECT_MEMORY_DIR=""
fi

# Build context string
CONTEXT=""

# Load self-model
if [[ -f "$MEMORY_DIR/self-model.md" ]]; then
    CONTEXT+="## Self-Model\n"
    CONTEXT+=$(cat "$MEMORY_DIR/self-model.md")
    CONTEXT+="\n\n"
fi

# Load project sticky memory
if [[ -n "$PROJECT_MEMORY_DIR" && -f "$PROJECT_MEMORY_DIR/sticky.md" ]]; then
    CONTEXT+="## Sticky Memory (this project)\n"
    CONTEXT+=$(cat "$PROJECT_MEMORY_DIR/sticky.md")
    CONTEXT+="\n\n"
fi

# Load tasks index
TASKS_DIR="$MEMORY_DIR/tasks"
if [[ -f "$TASKS_DIR/index.md" ]]; then
    CONTEXT+="## Tasks\n"
    CONTEXT+=$(cat "$TASKS_DIR/index.md")
    CONTEXT+="\n\n"
fi

# Load current task context if set
if [[ -f "$TASKS_DIR/current.md" ]]; then
    CURRENT_TASK=$(grep -o 'id: *[^ ]*' "$TASKS_DIR/current.md" 2>/dev/null | sed 's/id: *//' | head -1)
    if [[ -n "$CURRENT_TASK" && "$CURRENT_TASK" != "none" ]]; then
        # Find and load the task file
        TASK_FILE=$(find "$TASKS_DIR" -name "${CURRENT_TASK}*.md" -type f 2>/dev/null | head -1)
        if [[ -f "$TASK_FILE" ]]; then
            CONTEXT+="## Current Task\n"
            CONTEXT+=$(cat "$TASK_FILE")
            CONTEXT+="\n\n"
        fi
    fi
fi

# Load recent session index (last 5 entries)
if [[ -f "$MEMORY_DIR/global-index.md" ]]; then
    CONTEXT+="## Recent Sessions\n"
    CONTEXT+=$(head -20 "$MEMORY_DIR/global-index.md")
    CONTEXT+="\n\n"
fi

# Load working.md (preserved turns from last session)
if [[ -n "$PROJECT_MEMORY_DIR" ]]; then
    mkdir -p "$PROJECT_MEMORY_DIR"

    # Get branch-scoped working.md path
    WORKING_MD=""
    if [[ -n "$CWD" ]]; then
        BRANCH_PATH=$(cd "$CWD" 2>/dev/null && bash ~/.claude/memory-hooks/git.sh memory-path 2>/dev/null || echo "")
        if [[ -n "$BRANCH_PATH" && -f "$BRANCH_PATH" ]]; then
            WORKING_MD="$BRANCH_PATH"
        fi
    fi
    # Fallback to main working.md
    if [[ -z "$WORKING_MD" && -f "$PROJECT_MEMORY_DIR/working.md" ]]; then
        WORKING_MD="$PROJECT_MEMORY_DIR/working.md"
    fi

    # Create default working.md if nothing exists
    if [[ -z "$WORKING_MD" ]]; then
        WORKING_MD="$PROJECT_MEMORY_DIR/working.md"
        cat > "$WORKING_MD" << 'EOF'
# Working

## Preserved
EOF
    fi

    # Load working memory into context
    if [[ -f "$WORKING_MD" ]]; then
        CONTEXT+="## Working Memory (preserved turns)\n"
        CONTEXT+=$(cat "$WORKING_MD")
        CONTEXT+="\n\n"
    fi
fi

# Check for oversized files that need pruning (silent signal to Claude)
PRUNE_NEEDED=""
MAX_FILE_SIZE=2048
if [[ -n "$PROJECT_MEMORY_DIR" ]]; then
    for f in "$PROJECT_MEMORY_DIR"/*.md; do
        [[ -f "$f" ]] && [[ $(wc -c < "$f") -gt $MAX_FILE_SIZE ]] && PRUNE_NEEDED+="$(basename "$f") "
    done
fi
for f in "$MEMORY_DIR"/*.md "$TASKS_DIR"/*.md; do
    [[ -f "$f" ]] && [[ $(wc -c < "$f") -gt $MAX_FILE_SIZE ]] && PRUNE_NEEDED+="$(basename "$f") "
done

if [[ -n "$PRUNE_NEEDED" ]]; then
    CONTEXT+="\n[PRUNE: $PRUNE_NEEDED]\n"
fi

# Available tools for memory management
CONTEXT+="\n## Memory Tools\n"
CONTEXT+="- save(content): bash ~/.claude/memory-hooks/save.sh \"content\" → persist to working.md\n"
CONTEXT+="- status(): bash ~/.claude/memory-hooks/status.sh → check context size\n"
CONTEXT+="- worker.sh state [task]: get curated state for subagent\n"
CONTEXT+="- /churn N: run N iterations via subagents (you=loop, workers=do)\n"
CONTEXT+="- Edit sticky.md: persist facts across sessions\n"
CONTEXT+="- Edit working.md: direct edit for complex preservation\n"
CONTEXT+="- Edit tasks/Txxx.md: multi-session task state\n"
CONTEXT+="[!] Use /churn for long tasks. save() what matters before compaction.\n"

# Context budget: cap at 4KB
MAX_CONTEXT=4096
CONTEXT_SIZE=${#CONTEXT}
if [[ $CONTEXT_SIZE -gt $MAX_CONTEXT ]]; then
    CONTEXT="${CONTEXT:0:$MAX_CONTEXT}\n[TRUNCATED]"
fi

# Output JSON response with context injection
if [[ -n "$CONTEXT" ]]; then
    # Escape for JSON
    ESCAPED=$(echo -e "$CONTEXT" | jq -Rs .)
    echo "{\"continue\": true, \"hookSpecificOutput\": {\"additionalContext\": $ESCAPED}}"
else
    echo '{"continue": true}'
fi
