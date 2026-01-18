#!/bin/bash
# Save to working memory - Claude calls to preserve important context
# Usage: bash ~/.claude/memory-hooks/save.sh "content to preserve"
# Saves content to working.md for persistence across compaction/sessions

set -euo pipefail

PRESERVE="${1:-}"

if [[ -z "$PRESERVE" ]]; then
    echo "usage: save.sh \"content to preserve\""
    exit 1
fi

# Get branch-scoped working.md path from git.sh
WORKING_FILE=$(bash ~/.claude/memory-hooks/git.sh memory-path)
if [[ -z "$WORKING_FILE" ]]; then
    echo "err: could not determine memory path"
    exit 1
fi
mkdir -p "$(dirname "$WORKING_FILE")"

# Append to working memory (not overwrite)
echo "" >> "$WORKING_FILE"
echo "## Preserved ($(date +%H:%M))" >> "$WORKING_FILE"
echo "$PRESERVE" >> "$WORKING_FILE"

echo "saved→working.md"
