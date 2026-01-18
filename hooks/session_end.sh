#!/bin/bash
# Gentler Memory - Session End Hook
# Appends brief session reflection to log

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
MEMORY_DIR="$CLAUDE_DIR/memory"

# Read input JSON from stdin
INPUT=$(cat)

# Extract fields
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Encode project path
if [[ -n "$CWD" ]]; then
    PROJECT_ENCODED=$(echo "$CWD" | sed 's|/|-|g')
    PROJECT_MEMORY_DIR="$CLAUDE_DIR/projects/$PROJECT_ENCODED/memory"
else
    PROJECT_MEMORY_DIR=""
fi

# Ensure project memory directory exists
if [[ -n "$PROJECT_MEMORY_DIR" ]]; then
    mkdir -p "$PROJECT_MEMORY_DIR"

    # Create session-index.md if it doesn't exist
    if [[ ! -f "$PROJECT_MEMORY_DIR/session-index.md" ]]; then
        cat > "$PROJECT_MEMORY_DIR/session-index.md" << 'EOF'
# Project Session Index

| Date | Session | Notes |
|------|---------|-------|
EOF
    fi

    # Log session end
    DATE=$(date '+%Y-%m-%d %H:%M')
    SHORT_ID="${SESSION_ID:0:8}"
    echo "| $DATE | $SHORT_ID | ended |" >> "$PROJECT_MEMORY_DIR/session-index.md"
fi

# Simple acknowledgment
echo '{"continue": true}'
