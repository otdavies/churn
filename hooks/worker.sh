#!/bin/bash
# Ralph Loop Worker - spawns focused subagents with minimal context
# Usage: Called by Claude to spawn worker agents
#
# This script doesn't do the spawning - Claude does that via Task tool.
# This is a helper to format state for workers and collect results.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
MEMORY_DIR="$CLAUDE_DIR/memory"

ACTION="$1"
shift

case "$ACTION" in
    # Get current state formatted for a worker
    state)
        TASK_ID="${1:-none}"
        echo "## State"

        # Current task
        if [[ "$TASK_ID" != "none" ]]; then
            TASK_FILE=$(find "$MEMORY_DIR/tasks" -name "${TASK_ID}*.md" 2>/dev/null | head -1)
            if [[ -f "$TASK_FILE" ]]; then
                echo "### Task"
                cat "$TASK_FILE"
            fi
        fi

        # Working memory
        PROJECT_DIR=$(ls -td "$CLAUDE_DIR"/projects/*/ 2>/dev/null | head -1)
        if [[ -n "$PROJECT_DIR" && -f "$PROJECT_DIR/memory/working.md" ]]; then
            echo ""
            echo "### Working"
            cat "$PROJECT_DIR/memory/working.md"
        fi
        ;;

    # Save worker result
    result)
        RESULT="$1"
        PROJECT_DIR=$(ls -td "$CLAUDE_DIR"/projects/*/ 2>/dev/null | head -1)
        WORKING_FILE="$PROJECT_DIR/memory/working.md"
        mkdir -p "$(dirname "$WORKING_FILE")"

        # Append to working memory
        echo "" >> "$WORKING_FILE"
        echo "## Worker Result ($(date +%H:%M))" >> "$WORKING_FILE"
        echo "$RESULT" >> "$WORKING_FILE"
        echo "saved→working.md"
        ;;

    # Get loop counter
    loop)
        PROJECT_DIR=$(ls -td "$CLAUDE_DIR"/projects/*/ 2>/dev/null | head -1)
        LOOP_FILE="$PROJECT_DIR/memory/.loop"
        if [[ -f "$LOOP_FILE" ]]; then
            cat "$LOOP_FILE"
        else
            echo "0"
        fi
        ;;

    # Increment loop counter
    next)
        PROJECT_DIR=$(ls -td "$CLAUDE_DIR"/projects/*/ 2>/dev/null | head -1)
        LOOP_FILE="$PROJECT_DIR/memory/.loop"
        mkdir -p "$(dirname "$LOOP_FILE")"
        CURRENT=$(cat "$LOOP_FILE" 2>/dev/null || echo "0")
        echo $((CURRENT + 1)) > "$LOOP_FILE"
        echo $((CURRENT + 1))
        ;;

    *)
        echo "Usage: worker.sh [state|result|loop|next] [args]"
        exit 1
        ;;
esac
