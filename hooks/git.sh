#!/bin/bash
# Git utilities for churn system

CHURN_GIT_ORIGINAL_FILE="/tmp/churn_original_state_$$"

churn_git() {
    local action="$1"
    shift

    case "$action" in
        check)
            command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null
            ;;
        branch)
            local desc="$1"
            local sanitized=$(echo "$desc" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-30)
            local timestamp=$(date +%m%d-%H%M)
            local branch_name="churn/${sanitized}-${timestamp}"
            git checkout -b "$branch_name" 2>/dev/null && echo "$branch_name"
            ;;
        changes)
            git diff --name-only 2>/dev/null
            git diff --cached --name-only 2>/dev/null
            ;;
        commit)
            local msg="$1"
            git add -A 2>/dev/null && git commit -m "$msg" 2>/dev/null
            ;;
        diff-summary)
            git diff --stat 2>/dev/null
            git diff --cached --stat 2>/dev/null
            ;;
        log)
            local count="${1:-5}"
            git log --oneline -n "$count" 2>/dev/null
            ;;
        memory-path)
            local project_dir=$(ls -td "$HOME/.claude"/projects/*/ 2>/dev/null | head -1)
            if [[ -z "$project_dir" ]]; then
                return 1
            fi
            local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
            if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
                echo "${project_dir}memory/branches/${branch}/working.md"
            else
                echo "${project_dir}memory/working.md"
            fi
            ;;
        save-original)
            git rev-parse HEAD 2>/dev/null > "$CHURN_GIT_ORIGINAL_FILE"
            git diff 2>/dev/null >> "$CHURN_GIT_ORIGINAL_FILE"
            ;;
        original)
            cat "$CHURN_GIT_ORIGINAL_FILE" 2>/dev/null
            ;;
        clear-original)
            rm -f "$CHURN_GIT_ORIGINAL_FILE" 2>/dev/null
            ;;
        help)
            echo "Git utilities: check, branch, changes, commit, diff-summary, log, memory-path, save-original, original, clear-original, help"
            ;;
        *)
            echo "Unknown git action: $action" >&2
            return 1
            ;;
    esac
}
