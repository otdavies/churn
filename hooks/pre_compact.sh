#!/bin/bash
# Gentler Memory - Pre-Compaction Hook
# 1. Injects ultra-compressed shorthand instructions
# 2. Updates session index
# 3. Updates self-model session count

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
MEMORY_DIR="$CLAUDE_DIR/memory"

# Read input JSON from stdin
INPUT=$(cat)

# Extract fields
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Encode project path
if [[ -n "$CWD" ]]; then
    PROJECT_ENCODED=$(echo "$CWD" | sed 's|/|-|g')
    PROJECT_MEMORY_DIR="$CLAUDE_DIR/projects/$PROJECT_ENCODED/memory"
    PROJECT_NAME=$(basename "$CWD")
else
    PROJECT_MEMORY_DIR=""
    PROJECT_NAME="unknown"
fi

# Update session index
DATE=$(date '+%Y-%m-%d')
SHORT_ID="${SESSION_ID:0:8}"

# Extract topic from transcript (first user message, cleaned up)
TOPIC="session"
if [[ -f "$TRANSCRIPT_PATH" ]]; then
    # Get first user message, strip newlines, take first 50 chars, trim
    RAW=$(head -100 "$TRANSCRIPT_PATH" | jq -r 'select(.type == "human") | .message.content // empty' 2>/dev/null | head -1)
    if [[ -n "$RAW" ]]; then
        # Clean: remove newlines, collapse spaces, trim to 50 chars
        TOPIC=$(echo "$RAW" | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-50 | sed 's/ *$//')
        # If still empty or just whitespace
        [[ -z "${TOPIC// }" ]] && TOPIC="session"
    fi
fi

# Append to global index
mkdir -p "$MEMORY_DIR"
if [[ -f "$MEMORY_DIR/global-index.md" ]]; then
    # Add entry after header row
    echo "| $DATE | $PROJECT_NAME | $TOPIC | compacted |" >> "$MEMORY_DIR/global-index.md"
fi

# Update session count in self-model
if [[ -f "$MEMORY_DIR/self-model.md" ]]; then
    # Extract current count and increment (portable - no grep -P)
    CURRENT=$(sed -n 's/.*sess: *\([0-9]*\).*/\1/p' "$MEMORY_DIR/self-model.md" 2>/dev/null | head -1)
    [[ -z "$CURRENT" ]] && CURRENT=0
    NEW_COUNT=$((CURRENT + 1))

    # Update timestamp and count (matches template: *upd: X | sess: Y | ...*)
    sed -i.bak "s/\*upd: [^|]*| sess: [0-9]*/\*upd: $DATE | sess: $NEW_COUNT/" "$MEMORY_DIR/self-model.md"
    rm -f "$MEMORY_DIR/self-model.md.bak"
fi

# Build compaction instruction message (itself compressed)
read -r -d '' SHORTHAND_INSTRUCTIONS << 'EOF' || true
## COMPACT MODE

FIRST: Preserve what matters to working.md before compaction:
```bash
bash ~/.claude/memory-hooks/save.sh "key insights, decisions, state to preserve"
```

THEN: Compress summary to 1/3 size. YOUR shorthand, for yourself.

RULES:
- abbrev: fn/impl/cfg/auth/req/resp/err/ctx/usr/msg/db/api/dir/file/prj
- symbols: →∴≈✗✓?! (leads/therefore/approx/fail/done/uncertain/important)
- drop: articles, pronouns, "the", "I", pleasantries
- paths: src/c/A.ts not src/components/Auth.tsx

BEFORE: "I implemented a new authentication system using JWT tokens."
AFTER: "impl JWT auth+refresh"

Compress hard. working.md survives. You understand yourself.
EOF

# Calculate memory stats
STICKY_SIZE="0"
WORKING_SIZE="0"
if [[ -n "$PROJECT_MEMORY_DIR" ]]; then
    [[ -f "$PROJECT_MEMORY_DIR/sticky.md" ]] && STICKY_SIZE=$(wc -c < "$PROJECT_MEMORY_DIR/sticky.md" | tr -d ' ')
    [[ -f "$PROJECT_MEMORY_DIR/working.md" ]] && WORKING_SIZE=$(wc -c < "$PROJECT_MEMORY_DIR/working.md" | tr -d ' ')
fi
SELF_SIZE="0"
[[ -f "$MEMORY_DIR/self-model.md" ]] && SELF_SIZE=$(wc -c < "$MEMORY_DIR/self-model.md" | tr -d ' ')

TOTAL_KB=$(echo "scale=1; ($STICKY_SIZE + $WORKING_SIZE + $SELF_SIZE) / 1024" | bc)
STATUS="mem preserved: ${TOTAL_KB}kb (self:${SELF_SIZE}b sticky:${STICKY_SIZE}b working:${WORKING_SIZE}b)"

# Output JSON with shorthand instructions
ESCAPED=$(echo "$SHORTHAND_INSTRUCTIONS" | jq -Rs .)
echo "{\"continue\": true, \"reason\": \"$STATUS\", \"systemMessage\": $ESCAPED}"
