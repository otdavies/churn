#!/bin/bash
# Memory status - Claude calls to check context size
# Usage: bash ~/.claude/memory-hooks/status.sh

CLAUDE_DIR="$HOME/.claude"

# Find current transcript
TRANSCRIPT=$(ls -t "$CLAUDE_DIR"/projects/*/*.jsonl 2>/dev/null | head -1)
if [[ -z "$TRANSCRIPT" ]]; then
    echo "err: no transcript"
    exit 1
fi

# Get sizes
T_SIZE=$(wc -c < "$TRANSCRIPT")
T_LINES=$(wc -l < "$TRANSCRIPT")
T_KB=$((T_SIZE / 1024))

# Threshold warnings
WARN=""
[[ $T_KB -gt 500 ]] && WARN=" [!high]"
[[ $T_KB -gt 1000 ]] && WARN=" [!!critical]"

echo "ctx: ${T_KB}kb ${T_LINES}lines${WARN}"
