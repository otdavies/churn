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

# ============================================
# FLAG EXTRACTION: Extract [FLAG:type] markers from transcript
# ============================================
if [[ -n "$PROJECT_MEMORY_DIR" && -f "$TRANSCRIPT_PATH" ]]; then
    FLAGGED_FILE="$PROJECT_MEMORY_DIR/flagged.md"
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

    # Create flagged.md from template if missing
    if [[ ! -f "$FLAGGED_FILE" ]]; then
        cat > "$FLAGGED_FILE" << 'FLAGTEMPLATE'
# Flagged Items

## Prompt

## Progress

## Decisions

## Diffs

## Blockers

## Notes
FLAGTEMPLATE
    fi

    # Extract flags from transcript (looking in assistant messages)
    EXTRACTED_FLAGS=$(grep -oE '\[FLAG:[a-z]+\][^\n]*' "$TRANSCRIPT_PATH" 2>/dev/null || true)

    if [[ -n "$EXTRACTED_FLAGS" ]]; then
        # Process each flag
        while IFS= read -r flag_line; do
            [[ -z "$flag_line" ]] && continue

            # Parse type and content
            FLAG_TYPE=$(echo "$flag_line" | sed 's/\[FLAG:\([a-z]*\)\].*/\1/')
            FLAG_CONTENT=$(echo "$flag_line" | sed 's/\[FLAG:[a-z]*\] *//')

            case "$FLAG_TYPE" in
                prompt)
                    # Overwrite - replace entire Prompt section
                    sed -i.bak "/^## Prompt$/,/^## /{/^## Prompt$/!{/^## /!d}}" "$FLAGGED_FILE"
                    sed -i.bak "s|^## Prompt$|## Prompt\n[$TIMESTAMP] $FLAG_CONTENT|" "$FLAGGED_FILE"
                    ;;
                progress)
                    # Overwrite - replace entire Progress section
                    sed -i.bak "/^## Progress$/,/^## /{/^## Progress$/!{/^## /!d}}" "$FLAGGED_FILE"
                    sed -i.bak "s|^## Progress$|## Progress\n[$TIMESTAMP] $FLAG_CONTENT|" "$FLAGGED_FILE"
                    ;;
                decision)
                    # Append to Decisions, keep max 5 (FIFO)
                    sed -i.bak "/^## Decisions$/a\\
- [$TIMESTAMP] $FLAG_CONTENT" "$FLAGGED_FILE"
                    # Prune to last 5 entries in Decisions section
                    awk '/^## Decisions$/,/^## /{
                        if(/^- /) { count++; lines[count]=$0 }
                        else print
                        if(/^## / && !/^## Decisions$/) {
                            start = count > 5 ? count - 4 : 1
                            for(i=start; i<=count; i++) print lines[i]
                            count=0
                            delete lines
                        }
                    }' "$FLAGGED_FILE" > "$FLAGGED_FILE.tmp" && mv "$FLAGGED_FILE.tmp" "$FLAGGED_FILE"
                    ;;
                diff)
                    # Append to Diffs, keep max 10 (FIFO)
                    sed -i.bak "/^## Diffs$/a\\
- [$TIMESTAMP] $FLAG_CONTENT" "$FLAGGED_FILE"
                    # Prune to last 10 entries
                    awk '/^## Diffs$/,/^## /{
                        if(/^- /) { count++; lines[count]=$0 }
                        else print
                        if(/^## / && !/^## Diffs$/) {
                            start = count > 10 ? count - 9 : 1
                            for(i=start; i<=count; i++) print lines[i]
                            count=0
                            delete lines
                        }
                    }' "$FLAGGED_FILE" > "$FLAGGED_FILE.tmp" && mv "$FLAGGED_FILE.tmp" "$FLAGGED_FILE"
                    ;;
                blocker)
                    # Append to Blockers, keep max 5
                    sed -i.bak "/^## Blockers$/a\\
- [$TIMESTAMP] $FLAG_CONTENT" "$FLAGGED_FILE"
                    ;;
                note)
                    # Append to Notes, keep max 5 (FIFO)
                    sed -i.bak "/^## Notes$/a\\
- [$TIMESTAMP] $FLAG_CONTENT" "$FLAGGED_FILE"
                    # Prune to last 5 entries
                    awk '/^## Notes$/,/^## |$/{
                        if(/^- /) { count++; lines[count]=$0 }
                        else print
                    } END {
                        start = count > 5 ? count - 4 : 1
                        for(i=start; i<=count; i++) print lines[i]
                    }' "$FLAGGED_FILE" > "$FLAGGED_FILE.tmp" && mv "$FLAGGED_FILE.tmp" "$FLAGGED_FILE"
                    ;;
            esac
            rm -f "$FLAGGED_FILE.bak"
        done <<< "$EXTRACTED_FLAGS"
    fi
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

# ============================================
# SNAPSHOT: Capture project state and generate diff
# ============================================
SNAPSHOT_DIFF=""
if [[ -n "$CWD" ]]; then
    # Get current compaction number
    COMPACT_NUM=$(cat "$CLAUDE_DIR/projects/$PROJECT_ENCODED/snapshots/state" 2>/dev/null || echo "0")
    NEXT_COMPACT=$((COMPACT_NUM + 1))

    # Capture current state
    bash ~/.claude/memory-hooks/snapshot.sh capture "compact-$NEXT_COMPACT" "$CWD" 2>/dev/null || true

    # Generate diff for injection
    SNAPSHOT_DIFF=$(bash ~/.claude/memory-hooks/snapshot.sh inject "$CWD" 2>/dev/null || true)
fi

# ============================================
# TRACE EXTRACTION: Extract reasoning from transcript
# ============================================
if [[ -f "$TRANSCRIPT_PATH" ]]; then
    # Extract session ID from transcript path
    TRACE_SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl | cut -c1-8)

    # Extract traces in background (non-blocking)
    bash ~/.claude/memory-hooks/trace.sh extract "$TRACE_SESSION_ID" 2>/dev/null &

    # Update index
    bash ~/.claude/memory-hooks/trace.sh index 2>/dev/null || true
fi

# Calculate memory stats
WORKING_SIZE="0"
if [[ -n "$PROJECT_MEMORY_DIR" ]]; then
    [[ -f "$PROJECT_MEMORY_DIR/working.md" ]] && WORKING_SIZE=$(wc -c < "$PROJECT_MEMORY_DIR/working.md" | tr -d ' ')
fi
SELF_SIZE="0"
[[ -f "$MEMORY_DIR/self-model.md" ]] && SELF_SIZE=$(wc -c < "$MEMORY_DIR/self-model.md" | tr -d ' ')

TOTAL_KB=$(echo "scale=1; ($WORKING_SIZE + $SELF_SIZE) / 1024" | bc)
STATUS="mem preserved: ${TOTAL_KB}kb (self:${SELF_SIZE}b working:${WORKING_SIZE}b)"

# Build final system message with snapshot diff if available
FINAL_MESSAGE="$SHORTHAND_INSTRUCTIONS"
if [[ -n "$SNAPSHOT_DIFF" ]]; then
    FINAL_MESSAGE+="

$SNAPSHOT_DIFF"
fi

# Output JSON with shorthand instructions and snapshot diff
ESCAPED=$(echo "$FINAL_MESSAGE" | jq -Rs .)
echo "{\"continue\": true, \"reason\": \"$STATUS\", \"systemMessage\": $ESCAPED}"
