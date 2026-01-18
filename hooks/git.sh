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
            # Get project dir from CWD, not most-recent (which is unreliable)
            local cwd="${PWD:-$(pwd)}"
            local project_encoded=$(echo "$cwd" | sed 's|/|-|g')
            local project_dir="$HOME/.claude/projects/$project_encoded"

            if [[ ! -d "$project_dir" ]]; then
                # Fallback: try most recent (legacy behavior)
                project_dir=$(ls -td "$HOME/.claude"/projects/*/ 2>/dev/null | head -1)
            fi

            if [[ -z "$project_dir" ]]; then
                return 1
            fi

            local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
            if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
                # Sanitize branch name for filesystem (replace / with -)
                local safe_branch=$(echo "$branch" | sed 's|/|-|g')
                echo "${project_dir}/memory/branches/${safe_branch}/working.md"
            else
                echo "${project_dir}/memory/working.md"
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
        detect-build)
            # Detect build command for current project
            if [[ -f "package.json" ]]; then
                if grep -q '"typecheck"' package.json 2>/dev/null; then
                    echo "npm run typecheck"
                elif grep -q '"build"' package.json 2>/dev/null; then
                    echo "npm run build"
                else
                    echo "npm run build"
                fi
            elif [[ -f "Cargo.toml" ]]; then
                echo "cargo check"
            elif [[ -f "go.mod" ]]; then
                echo "go build ./..."
            elif [[ -f "Makefile" ]]; then
                if grep -q '^check:' Makefile 2>/dev/null; then
                    echo "make check"
                else
                    echo "make build"
                fi
            elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
                echo "python -m py_compile"
            else
                echo ""
            fi
            ;;
        detect-test)
            # Detect test command for current project
            if [[ -f "package.json" ]]; then
                if grep -q '"test"' package.json 2>/dev/null; then
                    echo "npm test"
                fi
            elif [[ -f "Cargo.toml" ]]; then
                echo "cargo test"
            elif [[ -f "go.mod" ]]; then
                echo "go test ./..."
            elif [[ -f "Makefile" ]]; then
                if grep -q '^test:' Makefile 2>/dev/null; then
                    echo "make test"
                fi
            elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
                echo "pytest"
            else
                echo ""
            fi
            ;;
        detect-lint)
            # Detect lint command for current project
            if [[ -f "package.json" ]]; then
                if grep -q '"lint"' package.json 2>/dev/null; then
                    echo "npm run lint"
                fi
            elif [[ -f "Cargo.toml" ]]; then
                echo "cargo clippy"
            elif [[ -f "go.mod" ]]; then
                echo "golangci-lint run"
            elif [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
                echo "ruff check ."
            else
                echo ""
            fi
            ;;
        validate)
            # Run validation and return status + output
            local build_cmd
            build_cmd=$(bash "$0" detect-build)

            if [[ -z "$build_cmd" ]]; then
                echo "build: skip (no build command detected)"
                return 0
            fi

            echo "running: $build_cmd"
            local output
            local exit_code
            output=$($build_cmd 2>&1) && exit_code=0 || exit_code=$?

            if [[ $exit_code -eq 0 ]]; then
                echo "build: PASS"
            else
                echo "build: FAIL (exit $exit_code)"
                echo "---"
                echo "$output" | head -20
            fi
            return $exit_code
            ;;
        project-path)
            # Get project memory directory from CWD
            local cwd="${PWD:-$(pwd)}"
            local project_encoded=$(echo "$cwd" | sed 's|/|-|g')
            echo "$HOME/.claude/projects/$project_encoded"
            ;;
        help)
            echo "Git utilities: check, branch, changes, commit, diff-summary, log, memory-path, save-original, original, clear-original, detect-build, detect-test, detect-lint, validate, project-path, help"
            ;;
        *)
            echo "Unknown git action: $action" >&2
            return 1
            ;;
    esac
}

# Run if called directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    churn_git "$@"
fi
