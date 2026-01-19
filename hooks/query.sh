#!/bin/bash
# Gentler Memory - Memory Query Tool
# Search past reasoning traces and memory files
#
# Usage:
#   query.sh grep "pattern"          - Search all traces for pattern
#   query.sh session [session-id]    - Get traces from specific session
#   query.sh file [path]             - Find traces mentioning a file
#   query.sh tag [tag]               - Find traces with specific tag
#   query.sh recent [n]              - Show n most recent traces
#   query.sh confused "question"     - Guided search for uncertainty

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
TRACES_DIR="$CLAUDE_DIR/memory/traces"
MEMORY_DIR="$CLAUDE_DIR/memory"

action="${1:-help}"

# Helper: format trace output
format_trace() {
    local trace_file="$1"
    local max_lines="${2:-20}"

    if [[ ! -f "$trace_file" ]]; then
        return
    fi

    local session=$(basename "$(dirname "$trace_file")")
    local trace_name=$(basename "$trace_file" .md)
    local date=$(grep -m1 '^date:' "$trace_file" 2>/dev/null | sed 's/date: *//' | cut -c1-10)
    local tags=$(grep -m1 '^tags:' "$trace_file" 2>/dev/null | sed 's/tags: *//')

    echo "---"
    echo "Trace: $trace_name"
    echo "Session: $session | Date: $date | Tags: $tags"
    echo ""

    # Extract reasoning section (limited)
    sed -n '/^## Reasoning$/,/^## /p' "$trace_file" 2>/dev/null | head -$max_lines

    echo ""
}

case "$action" in
    grep)
        PATTERN="${2:-}"

        if [[ -z "$PATTERN" ]]; then
            echo "error: grep requires a pattern"
            exit 1
        fi

        echo "Searching traces for: $PATTERN"
        echo ""

        # Search in trace files
        RESULTS=$(grep -ril "$PATTERN" "$TRACES_DIR/by-session" 2>/dev/null || true)

        if [[ -z "$RESULTS" ]]; then
            echo "No traces found matching '$PATTERN'"

            # Suggest searching memory files
            echo ""
            echo "Also searched in memory files:"
            grep -l "$PATTERN" "$MEMORY_DIR"/*.md 2>/dev/null || echo "  (no matches)"
            exit 0
        fi

        # Show results (limited to 5)
        COUNT=0
        while IFS= read -r trace_file; do
            [[ -z "$trace_file" ]] && continue
            format_trace "$trace_file" 15
            COUNT=$((COUNT + 1))
            [[ $COUNT -ge 5 ]] && break
        done <<< "$RESULTS"

        TOTAL=$(echo "$RESULTS" | wc -l | tr -d ' ')
        if [[ $TOTAL -gt 5 ]]; then
            echo "... and $((TOTAL - 5)) more matches"
        fi
        ;;

    session)
        SESSION_ID="${2:-}"

        if [[ -z "$SESSION_ID" ]]; then
            # List available sessions
            echo "Available sessions:"
            find "$TRACES_DIR/by-session" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r dir; do
                session=$(basename "$dir")
                count=$(find "$dir" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
                echo "  $session ($count traces)"
            done
            exit 0
        fi

        SESSION_DIR="$TRACES_DIR/by-session/$SESSION_ID"

        if [[ ! -d "$SESSION_DIR" ]]; then
            echo "error: session $SESSION_ID not found"
            exit 1
        fi

        echo "Traces from session $SESSION_ID:"
        echo ""

        find "$SESSION_DIR" -name "*.md" -type f | sort | while read -r trace_file; do
            format_trace "$trace_file" 10
        done
        ;;

    file)
        FILE_PATH="${2:-}"

        if [[ -z "$FILE_PATH" ]]; then
            echo "error: file requires a path"
            exit 1
        fi

        # Extract filename for broader search
        FILENAME=$(basename "$FILE_PATH")

        echo "Searching for traces mentioning: $FILE_PATH"
        echo ""

        # Search for file path or filename
        RESULTS=$(grep -ril -e "$FILE_PATH" -e "$FILENAME" "$TRACES_DIR/by-session" 2>/dev/null || true)

        if [[ -z "$RESULTS" ]]; then
            echo "No traces found mentioning '$FILE_PATH'"
            exit 0
        fi

        while IFS= read -r trace_file; do
            [[ -z "$trace_file" ]] && continue
            format_trace "$trace_file" 15
        done <<< "$RESULTS"
        ;;

    tag)
        TAG="${2:-}"

        if [[ -z "$TAG" ]]; then
            # List available tags
            echo "Available tags:"
            grep -h '^tags:' "$TRACES_DIR/by-session"/*/*.md 2>/dev/null | \
                sed 's/tags: *//' | tr ',' '\n' | sed 's/^ *//;s/ *$//' | \
                sort | uniq -c | sort -rn | head -20
            exit 0
        fi

        echo "Traces with tag: $TAG"
        echo ""

        grep -ril "^tags:.*$TAG" "$TRACES_DIR/by-session" 2>/dev/null | while read -r trace_file; do
            format_trace "$trace_file" 10
        done
        ;;

    recent)
        N="${2:-5}"

        echo "Most recent $N traces:"
        echo ""

        find "$TRACES_DIR/by-session" -name "*.md" -type f 2>/dev/null | \
            xargs ls -t 2>/dev/null | head -$N | while read -r trace_file; do
            format_trace "$trace_file" 10
        done
        ;;

    confused)
        QUESTION="${2:-}"

        if [[ -z "$QUESTION" ]]; then
            echo "error: confused requires a question"
            echo "Usage: query.sh confused \"what is the auth flow?\""
            exit 1
        fi

        echo "Searching for context about: $QUESTION"
        echo ""

        # Extract keywords from question
        KEYWORDS=$(echo "$QUESTION" | grep -oE '\b[a-zA-Z]{4,}\b' | tr '[:upper:]' '[:lower:]' | sort -u)

        # Search for each keyword
        MATCHED_FILES=""
        for keyword in $KEYWORDS; do
            # Skip common words
            [[ "$keyword" =~ ^(what|where|when|which|that|this|with|from|have|does|should)$ ]] && continue

            RESULTS=$(grep -ril "$keyword" "$TRACES_DIR/by-session" 2>/dev/null || true)
            if [[ -n "$RESULTS" ]]; then
                MATCHED_FILES+="$RESULTS"$'\n'
            fi
        done

        if [[ -z "$MATCHED_FILES" ]]; then
            echo "No relevant traces found."
            echo ""
            echo "Try searching memory files directly:"
            echo "  grep -r \"$QUESTION\" ~/.claude/memory/"
            exit 0
        fi

        # Deduplicate and show top results
        UNIQUE_FILES=$(echo "$MATCHED_FILES" | sort | uniq -c | sort -rn | head -5 | awk '{print $2}')

        echo "Potentially relevant traces:"
        echo ""

        while IFS= read -r trace_file; do
            [[ -z "$trace_file" ]] && continue
            format_trace "$trace_file" 15
        done <<< "$UNIQUE_FILES"
        ;;

    help|*)
        echo "Memory Query Tool"
        echo ""
        echo "Usage: query.sh <action> [args]"
        echo ""
        echo "Actions:"
        echo "  grep \"pattern\"      Search all traces for pattern"
        echo "  session [id]        Get traces from session (list if no id)"
        echo "  file [path]         Find traces mentioning a file"
        echo "  tag [tag]           Find traces by tag (list if no tag)"
        echo "  recent [n]          Show n most recent traces (default: 5)"
        echo "  confused \"q\"        Guided search for uncertainty"
        echo ""
        echo "Examples:"
        echo "  query.sh grep \"authentication\""
        echo "  query.sh file src/auth.ts"
        echo "  query.sh tag decision"
        echo "  query.sh confused \"how does the login work?\""
        ;;
esac
