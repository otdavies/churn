#!/bin/bash
# Gentler Memory - Shadow Repository Snapshot Tool
# External observer that tracks project state without touching project's git
#
# Usage:
#   snapshot.sh init [project_dir]     - Initialize shadow repo for a project
#   snapshot.sh capture [label]        - Capture current state with label
#   snapshot.sh diff [from] [to]       - Generate diff between two labels
#   snapshot.sh inject                 - Format latest diff for context injection
#   snapshot.sh gc                     - Clean up old snapshots
#   snapshot.sh reset                  - Wipe shadow repo and start fresh
#   snapshot.sh status                 - Show current snapshot state

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"

# Get project directory from argument or current directory
PROJECT_DIR="${2:-$(pwd)}"

# Encode project path for directory name
PROJECT_ENCODED=$(echo "$PROJECT_DIR" | sed 's|/|-|g')
SHADOW_BASE="$CLAUDE_DIR/projects/$PROJECT_ENCODED"
SHADOW_REPO="$SHADOW_BASE/shadow-repo"
DIFFS_DIR="$SHADOW_BASE/snapshots/diffs"
STATE_FILE="$SHADOW_BASE/snapshots/state"

# Exclusion patterns for rsync
EXCLUDES=(
    '.git'
    'node_modules'
    '.next'
    'dist'
    'build'
    '__pycache__'
    '*.pyc'
    '.venv'
    'venv'
    '.env'
    '.env.*'
    '*.log'
    '.DS_Store'
    'coverage'
    '.nyc_output'
    'target'  # Rust
    'vendor'  # Go
)

build_exclude_args() {
    local args=""
    for pattern in "${EXCLUDES[@]}"; do
        args+="--exclude='$pattern' "
    done
    echo "$args"
}

action="${1:-help}"

case "$action" in
    init)
        # Initialize shadow repo for project
        mkdir -p "$SHADOW_REPO"
        mkdir -p "$DIFFS_DIR"

        if [[ ! -d "$SHADOW_REPO/.git" ]]; then
            cd "$SHADOW_REPO"
            git init -q
            git config user.email "shadow@claude.local"
            git config user.name "Claude Shadow"

            # Create initial .gitignore
            cat > .gitignore << 'IGNORE'
# Shadow repo ignores (for nested .git dirs)
.git/
IGNORE

            git add .gitignore
            git commit -q -m "Shadow repo initialized" --allow-empty
            echo "init: shadow repo created at $SHADOW_REPO"
        else
            echo "init: shadow repo already exists"
        fi

        # Initialize state file
        echo "0" > "$STATE_FILE"
        ;;

    capture)
        LABEL="${2:-snapshot}"

        # Ensure shadow repo exists
        if [[ ! -d "$SHADOW_REPO/.git" ]]; then
            bash "$0" init "$PROJECT_DIR"
        fi

        # Build exclude arguments
        EXCLUDE_ARGS=$(build_exclude_args)

        # Sync project files to shadow repo
        eval rsync -a --delete $EXCLUDE_ARGS "'$PROJECT_DIR/'" "'$SHADOW_REPO/'"

        # Commit the snapshot
        cd "$SHADOW_REPO"
        git add -A

        TIMESTAMP=$(date -Iseconds)
        if git diff --cached --quiet; then
            # No changes, but still tag for reference
            git commit -q -m "$LABEL: $TIMESTAMP (no changes)" --allow-empty
        else
            CHANGES=$(git diff --cached --stat | tail -1)
            git commit -q -m "$LABEL: $TIMESTAMP" -m "$CHANGES"
        fi

        # Tag for easy reference (overwrite if exists)
        git tag -f "$LABEL" > /dev/null 2>&1

        # Update state counter if this is a compact label
        if [[ "$LABEL" == compact-* ]]; then
            CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
            echo "$((CURRENT + 1))" > "$STATE_FILE"
        fi

        echo "capture: $LABEL at $(git rev-parse --short HEAD)"
        ;;

    diff)
        FROM="${2:-session-start}"
        TO="${3:-HEAD}"

        if [[ ! -d "$SHADOW_REPO/.git" ]]; then
            echo "error: shadow repo not initialized"
            exit 1
        fi

        cd "$SHADOW_REPO"

        # Check if tags/refs exist
        if ! git rev-parse "$FROM" > /dev/null 2>&1; then
            echo "error: ref '$FROM' not found"
            exit 1
        fi
        if ! git rev-parse "$TO" > /dev/null 2>&1; then
            echo "error: ref '$TO' not found"
            exit 1
        fi

        # Generate diff summary
        echo "## Changes: $FROM → $TO"
        echo ""

        # Get stats
        STAT=$(git diff --stat "$FROM".."$TO" 2>/dev/null || true)
        if [[ -z "$STAT" ]]; then
            echo "No changes detected."
            exit 0
        fi

        # Summary line
        SUMMARY=$(echo "$STAT" | tail -1)
        echo "**Summary**: $SUMMARY"
        echo ""

        # File breakdown
        echo "### Files Changed"
        git diff --stat --stat-width=60 "$FROM".."$TO" | head -20
        echo ""

        # Actual diff preview (limited)
        echo "### Diff Preview (first 100 lines)"
        echo '```diff'
        git diff "$FROM".."$TO" | head -100
        echo '```'
        ;;

    inject)
        # Format the latest diff for context injection
        if [[ ! -d "$SHADOW_REPO/.git" ]]; then
            echo ""
            exit 0
        fi

        cd "$SHADOW_REPO"

        # Find latest compact tag
        COMPACT_NUM=$(cat "$STATE_FILE" 2>/dev/null || echo "0")

        if [[ "$COMPACT_NUM" -eq 0 ]]; then
            # First compaction - diff from session-start
            FROM="session-start"
            TO="HEAD"
        else
            # Subsequent compaction - diff from last compact
            LAST_COMPACT=$((COMPACT_NUM))
            FROM="compact-$LAST_COMPACT"
            TO="HEAD"
        fi

        # Check if we have valid refs
        if ! git rev-parse "$FROM" > /dev/null 2>&1; then
            echo ""
            exit 0
        fi

        # Generate compact diff summary for injection
        STAT=$(git diff --stat "$FROM".."$TO" 2>/dev/null || true)
        if [[ -z "$STAT" ]]; then
            echo ""
            exit 0
        fi

        echo "## Project Changes (since last checkpoint)"
        echo ""
        SUMMARY=$(echo "$STAT" | tail -1)
        echo "$SUMMARY"
        echo ""
        echo "### Modified Files"
        git diff --stat --stat-width=50 "$FROM".."$TO" | head -15
        echo ""
        echo "### Sample Changes"
        echo '```diff'
        git diff "$FROM".."$TO" -- '*.ts' '*.js' '*.py' '*.go' '*.rs' '*.sh' '*.md' 2>/dev/null | head -50
        echo '```'
        ;;

    gc)
        # Garbage collect old snapshots
        if [[ ! -d "$SHADOW_REPO/.git" ]]; then
            echo "gc: no shadow repo"
            exit 0
        fi

        cd "$SHADOW_REPO"

        # Keep only last 5 compact tags, delete older ones
        COMPACT_TAGS=$(git tag -l 'compact-*' | sort -t'-' -k2 -n)
        TAG_COUNT=$(echo "$COMPACT_TAGS" | wc -l | tr -d ' ')

        if [[ "$TAG_COUNT" -gt 5 ]]; then
            DELETE_COUNT=$((TAG_COUNT - 5))
            TO_DELETE=$(echo "$COMPACT_TAGS" | head -n "$DELETE_COUNT")
            for tag in $TO_DELETE; do
                git tag -d "$tag" > /dev/null 2>&1 || true
            done
            echo "gc: deleted $DELETE_COUNT old compact tags"
        fi

        # Run git gc
        git gc --quiet
        echo "gc: complete"
        ;;

    reset)
        # Wipe shadow repo and start fresh
        if [[ -d "$SHADOW_REPO" ]]; then
            rm -rf "$SHADOW_REPO"
            echo "reset: shadow repo deleted"
        fi
        if [[ -d "$DIFFS_DIR" ]]; then
            rm -rf "$DIFFS_DIR"
        fi
        rm -f "$STATE_FILE"

        # Reinitialize
        bash "$0" init "$PROJECT_DIR"
        ;;

    status)
        if [[ ! -d "$SHADOW_REPO/.git" ]]; then
            echo "status: no shadow repo initialized"
            exit 0
        fi

        cd "$SHADOW_REPO"

        COMPACT_NUM=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
        TAGS=$(git tag -l | wc -l | tr -d ' ')
        COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo "0")
        SIZE=$(du -sh "$SHADOW_REPO/.git" 2>/dev/null | cut -f1)

        echo "status: $COMMITS commits, $TAGS tags, $COMPACT_NUM compactions, $SIZE"
        ;;

    help|*)
        echo "Shadow Repository Snapshot Tool"
        echo ""
        echo "Usage: snapshot.sh <action> [args]"
        echo ""
        echo "Actions:"
        echo "  init [project_dir]   Initialize shadow repo"
        echo "  capture [label]      Capture project state with label"
        echo "  diff [from] [to]     Generate diff between refs"
        echo "  inject               Format latest diff for context"
        echo "  gc                   Clean up old snapshots"
        echo "  reset                Wipe and reinitialize"
        echo "  status               Show snapshot state"
        ;;
esac
