#!/bin/bash
# Save to working memory - Claude calls to preserve important context
# Usage: bash ~/.claude/memory-hooks/save.sh "content to preserve"
# Saves content to working.md for persistence across compaction/sessions

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
PRESERVE="${1:-}"

if [[ -z "$PRESERVE" ]]; then
    echo "usage: save.sh \"content to preserve\""
    exit 1
fi

# Find current project from most recent transcript
TRANSCRIPT=$(ls -t "$CLAUDE_DIR"/projects/*/*.jsonl 2>/dev/null | head -1)
if [[ -z "$TRANSCRIPT" ]]; then
    echo "err: no transcript"
    exit 1
fi

# Extract project dir
PROJECT_DIR=$(dirname "$TRANSCRIPT")
WORKING_FILE="$PROJECT_DIR/memory/working.md"
mkdir -p "$(dirname "$WORKING_FILE")"

# Append to working memory (not overwrite)
echo "" >> "$WORKING_FILE"
echo "## Preserved ($(date +%H:%M))" >> "$WORKING_FILE"
echo "$PRESERVE" >> "$WORKING_FILE"

echo "saved→working.md"
