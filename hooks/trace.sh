#!/bin/bash
# Gentler Memory - Trace Extraction Tool
# Extracts reasoning traces from Claude Code transcripts into searchable markdown files
#
# Usage:
#   trace.sh extract [session-id]    - Extract traces from a session
#   trace.sh index                   - Rebuild trace index
#   trace.sh archive                 - Archive old traces
#   trace.sh status                  - Show trace storage stats

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
TRACES_DIR="$CLAUDE_DIR/memory/traces"
INDEX_FILE="$TRACES_DIR/index.md"

# Ensure directories exist
mkdir -p "$TRACES_DIR/by-session"

action="${1:-help}"

case "$action" in
    extract)
        SESSION_ID="${2:-}"

        # Find transcript file
        TRANSCRIPT=""
        if [[ -n "$SESSION_ID" ]]; then
            # Look for specific session
            TRANSCRIPT=$(find "$CLAUDE_DIR/projects" -name "*.jsonl" -path "*$SESSION_ID*" 2>/dev/null | head -1)
        fi

        if [[ -z "$TRANSCRIPT" ]]; then
            # Try to find most recent transcript
            TRANSCRIPT=$(find "$CLAUDE_DIR/projects" -name "*.jsonl" -type f 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
        fi

        if [[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]]; then
            echo "error: no transcript found"
            exit 1
        fi

        # Get session ID from filename if not provided
        if [[ -z "$SESSION_ID" ]]; then
            SESSION_ID=$(basename "$TRANSCRIPT" .jsonl | cut -c1-8)
        fi

        SESSION_DIR="$TRACES_DIR/by-session/$SESSION_ID"
        mkdir -p "$SESSION_DIR"

        # Extract thinking blocks from transcript
        TRACE_NUM=1
        DATE=$(date -Iseconds)

        # Process JSONL - look for assistant messages with thinking
        while IFS= read -r line; do
            # Check if this is an assistant message with thinking
            TYPE=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
            [[ "$TYPE" != "assistant" ]] && continue

            # Extract thinking content
            THINKING=$(echo "$line" | jq -r '.message.content[]? | select(.type == "thinking") | .thinking // empty' 2>/dev/null)
            [[ -z "$THINKING" ]] && continue

            # Get context - try to find the preceding user message
            CONTEXT="(context not available)"

            # Generate a short description from first line of thinking
            SHORT_DESC=$(echo "$THINKING" | head -1 | cut -c1-50 | sed 's/[^a-zA-Z0-9 ]/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g' | sed 's/^ *//;s/ *$//')
            [[ -z "$SHORT_DESC" ]] && SHORT_DESC="trace"

            # Extract keywords (common programming terms)
            KEYWORDS=$(echo "$THINKING" | grep -oE '\b(function|class|method|api|error|fix|implement|refactor|test|config|auth|database|component|hook|state|props|route|endpoint|query|mutation)\b' | sort -u | head -5 | tr '\n' ', ' | sed 's/, $//')
            [[ -z "$KEYWORDS" ]] && KEYWORDS="general"

            # Determine tags based on content
            TAGS="trace"
            echo "$THINKING" | grep -qi "decision\|choose\|chose\|option" && TAGS+=", decision"
            echo "$THINKING" | grep -qi "error\|fail\|bug\|issue" && TAGS+=", error"
            echo "$THINKING" | grep -qi "implement\|add\|create\|build" && TAGS+=", implementation"
            echo "$THINKING" | grep -qi "refactor\|improve\|clean\|optimize" && TAGS+=", refactor"

            # Create trace file
            TRACE_FILE="$SESSION_DIR/$(printf '%03d' $TRACE_NUM)-${SHORT_DESC:0:30}.md"

            cat > "$TRACE_FILE" << TRACEEOF
# Trace: $SHORT_DESC

date: $DATE
session: $SESSION_ID
tags: $TAGS
keywords: $KEYWORDS

## Reasoning

$THINKING

## Keywords

$KEYWORDS
TRACEEOF

            TRACE_NUM=$((TRACE_NUM + 1))
        done < "$TRANSCRIPT"

        TOTAL=$((TRACE_NUM - 1))
        echo "extract: $TOTAL traces from session $SESSION_ID"
        ;;

    index)
        # Rebuild the trace index
        echo "# Trace Index" > "$INDEX_FILE"
        echo "" >> "$INDEX_FILE"
        echo "| date | session | trace | tags | keywords |" >> "$INDEX_FILE"
        echo "|------|---------|-------|------|----------|" >> "$INDEX_FILE"

        # Process all trace files
        find "$TRACES_DIR/by-session" -name "*.md" -type f 2>/dev/null | sort -r | while read -r trace_file; do
            SESSION=$(basename "$(dirname "$trace_file")")
            TRACE_NAME=$(basename "$trace_file" .md)

            # Extract metadata from trace file
            TRACE_DATE=$(grep -m1 '^date:' "$trace_file" 2>/dev/null | sed 's/date: *//' | cut -c1-10)
            TAGS=$(grep -m1 '^tags:' "$trace_file" 2>/dev/null | sed 's/tags: *//')
            KEYWORDS=$(grep -m1 '^keywords:' "$trace_file" 2>/dev/null | sed 's/keywords: *//' | cut -c1-30)

            [[ -z "$TRACE_DATE" ]] && TRACE_DATE="unknown"
            [[ -z "$TAGS" ]] && TAGS="-"
            [[ -z "$KEYWORDS" ]] && KEYWORDS="-"

            echo "| $TRACE_DATE | $SESSION | $TRACE_NAME | $TAGS | $KEYWORDS |" >> "$INDEX_FILE"
        done

        INDEX_COUNT=$(grep -c '^|' "$INDEX_FILE" 2>/dev/null || echo "0")
        INDEX_COUNT=$((INDEX_COUNT - 2))  # Subtract header rows
        echo "index: $INDEX_COUNT traces indexed"
        ;;

    archive)
        # Archive traces older than 7 days
        ARCHIVE_DIR="$TRACES_DIR/archive/$(date +%Y-%m)"
        mkdir -p "$ARCHIVE_DIR"

        ARCHIVED=0
        find "$TRACES_DIR/by-session" -name "*.md" -type f -mtime +7 2>/dev/null | while read -r trace_file; do
            SESSION=$(basename "$(dirname "$trace_file")")
            ARCHIVE_SESSION_DIR="$ARCHIVE_DIR/$SESSION"
            mkdir -p "$ARCHIVE_SESSION_DIR"
            mv "$trace_file" "$ARCHIVE_SESSION_DIR/"
            ARCHIVED=$((ARCHIVED + 1))
        done

        # Clean up empty session directories
        find "$TRACES_DIR/by-session" -type d -empty -delete 2>/dev/null || true

        echo "archive: moved old traces to $ARCHIVE_DIR"
        ;;

    status)
        HOT_COUNT=$(find "$TRACES_DIR/by-session" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
        ARCHIVE_COUNT=$(find "$TRACES_DIR/archive" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
        TOTAL_SIZE=$(du -sh "$TRACES_DIR" 2>/dev/null | cut -f1)
        SESSION_COUNT=$(find "$TRACES_DIR/by-session" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

        echo "status: $HOT_COUNT hot traces, $ARCHIVE_COUNT archived, $SESSION_COUNT sessions, $TOTAL_SIZE total"
        ;;

    help|*)
        echo "Trace Extraction Tool"
        echo ""
        echo "Usage: trace.sh <action> [args]"
        echo ""
        echo "Actions:"
        echo "  extract [session-id]   Extract traces from transcript"
        echo "  index                  Rebuild trace index"
        echo "  archive                Archive old traces (>7 days)"
        echo "  status                 Show storage stats"
        ;;
esac
