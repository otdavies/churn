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

        # ============================================
        # CHURN LIFECYCLE ACTIONS
        # ============================================

        churn-base)
            # Find the commit before the first churn commit on this branch
            # Returns the parent of the first "churn [" commit
            local first_churn_hash
            first_churn_hash=$(git log --oneline --reverse --grep="^churn \[" 2>/dev/null | head -1 | cut -d' ' -f1)

            if [[ -n "$first_churn_hash" ]]; then
                # Get parent of first churn commit
                local base
                base=$(git rev-parse "${first_churn_hash}^" 2>/dev/null)
                if [[ -n "$base" ]]; then
                    echo "$base"
                    return 0
                fi
            fi

            # Fallback: try to find merge-base with main/master
            local main_branch
            if git rev-parse --verify main &>/dev/null; then
                main_branch="main"
            elif git rev-parse --verify master &>/dev/null; then
                main_branch="master"
            else
                echo "error: cannot determine base commit" >&2
                return 1
            fi

            git merge-base "$main_branch" HEAD 2>/dev/null
            ;;

        churn-commits)
            # List all commits since base for summarization
            local base="$1"
            if [[ -z "$base" ]]; then
                base=$(bash "$0" churn-base 2>/dev/null)
            fi

            if [[ -z "$base" ]]; then
                echo "error: no base commit found" >&2
                return 1
            fi

            git log --oneline "$base"..HEAD 2>/dev/null
            ;;

        finalize)
            # Squash all commits since base into one
            local base="$1"
            local message="$2"

            if [[ -z "$base" || -z "$message" ]]; then
                echo "error: finalize requires base commit and message" >&2
                return 1
            fi

            # Check for uncommitted changes
            if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
                echo "error: uncommitted changes - commit or stash first" >&2
                return 1
            fi

            # Store recovery point
            local recovery_hash
            recovery_hash=$(git rev-parse HEAD)
            echo "$recovery_hash" > /tmp/churn_recovery_$$

            # Soft reset to base, then commit with new message
            git reset --soft "$base" 2>/dev/null || {
                echo "error: git reset failed" >&2
                return 1
            }

            git commit -m "$message" 2>/dev/null || {
                echo "error: git commit failed" >&2
                # Attempt recovery
                git reset --hard "$recovery_hash" 2>/dev/null
                return 1
            }

            local new_hash
            new_hash=$(git rev-parse --short HEAD)
            echo "squashed: $new_hash (recovery: $recovery_hash)"
            ;;

        rename-branch)
            # Rename current branch
            local new_name="$1"

            if [[ -z "$new_name" ]]; then
                echo "error: rename-branch requires new name" >&2
                return 1
            fi

            local current
            current=$(git branch --show-current 2>/dev/null)

            if [[ -z "$current" ]]; then
                echo "error: not on a branch" >&2
                return 1
            fi

            git branch -m "$current" "$new_name" 2>/dev/null && echo "renamed: $current → $new_name"
            ;;

        abort-finalize)
            # Restore from recovery point
            local recovery_file="/tmp/churn_recovery_$$"

            if [[ -f "$recovery_file" ]]; then
                local hash
                hash=$(cat "$recovery_file")
                git reset --hard "$hash" 2>/dev/null && {
                    rm -f "$recovery_file"
                    echo "restored: $hash"
                }
            else
                echo "error: no recovery point found" >&2
                return 1
            fi
            ;;

        churn-state)
            # Get current churn state for working.md
            local branch
            branch=$(git branch --show-current 2>/dev/null)

            if [[ "$branch" == churn/* ]]; then
                local base
                base=$(bash "$0" churn-base 2>/dev/null)
                local commit_count
                commit_count=$(git rev-list --count "${base}..HEAD" 2>/dev/null || echo "0")
                echo "churn-branch: $branch"
                echo "churn-base: ${base:0:8}"
                echo "churn-commits: $commit_count"
            else
                echo "not on churn branch"
            fi
            ;;

        help)
            echo "Git utilities: check, branch, changes, commit, diff-summary, log, memory-path,"
            echo "  save-original, original, clear-original, detect-build, detect-test, detect-lint,"
            echo "  validate, project-path, churn-base, churn-commits, finalize, rename-branch,"
            echo "  abort-finalize, churn-state, help"
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
