#!/bin/bash
# Churn Worker - spawns focused subagents with minimal context
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

        # Working memory (branch-scoped)
        WORKING_FILE=$(bash ~/.claude/memory-hooks/git.sh memory-path 2>/dev/null)
        if [[ -n "$WORKING_FILE" && -f "$WORKING_FILE" ]]; then
            echo ""
            echo "### Working"
            cat "$WORKING_FILE"
        fi
        ;;

    # Save worker result
    result)
        RESULT="$1"
        WORKING_FILE=$(bash ~/.claude/memory-hooks/git.sh memory-path 2>/dev/null)
        mkdir -p "$(dirname "$WORKING_FILE")"

        # Append to working memory
        echo "" >> "$WORKING_FILE"
        echo "## Worker Result ($(date +%H:%M))" >> "$WORKING_FILE"
        echo "$RESULT" >> "$WORKING_FILE"
        echo "saved→working.md"
        ;;

    # Get loop counter
    loop)
        PROJECT_DIR=$(bash ~/.claude/memory-hooks/git.sh project-path 2>/dev/null)
        if [[ -z "$PROJECT_DIR" ]]; then
            PROJECT_DIR=$(ls -td "$CLAUDE_DIR"/projects/*/ 2>/dev/null | head -1)
        fi
        LOOP_FILE="$PROJECT_DIR/memory/.loop"
        if [[ -f "$LOOP_FILE" ]]; then
            cat "$LOOP_FILE"
        else
            echo "0"
        fi
        ;;

    # Increment loop counter
    next)
        PROJECT_DIR=$(bash ~/.claude/memory-hooks/git.sh project-path 2>/dev/null)
        if [[ -z "$PROJECT_DIR" ]]; then
            PROJECT_DIR=$(ls -td "$CLAUDE_DIR"/projects/*/ 2>/dev/null | head -1)
        fi
        LOOP_FILE="$PROJECT_DIR/memory/.loop"
        mkdir -p "$(dirname "$LOOP_FILE")"
        CURRENT=$(cat "$LOOP_FILE" 2>/dev/null || echo "0")
        echo $((CURRENT + 1)) > "$LOOP_FILE"
        echo $((CURRENT + 1))
        ;;

    # Get git state summary
    git-state)
        if ! command -v git &>/dev/null; then
            echo "branch: n/a | uncommitted: n/a"
            exit 0
        fi
        if ! git rev-parse --git-dir &>/dev/null 2>&1; then
            echo "branch: n/a | uncommitted: n/a"
            exit 0
        fi
        BRANCH=$(git branch --show-current 2>/dev/null || echo "detached")
        UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        echo "branch: $BRANCH | uncommitted: $UNCOMMITTED files"
        ;;

    *)
        echo "Usage: worker.sh [state|result|loop|next] [args]"
        exit 1
        ;;
esac
