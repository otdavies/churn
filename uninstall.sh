#!/bin/bash
# Gentler Memory for Claude Code - Uninstaller
# Removes the memory system while optionally preserving memory files

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
MEMORY_DIR="$CLAUDE_DIR/memory"
HOOKS_DIR="$CLAUDE_DIR/memory-hooks"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "Uninstalling Gentler Memory for Claude Code..."
echo ""

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    exit 1
fi

# Remove hooks from settings.json
if [[ -f "$SETTINGS_FILE" ]]; then
    echo "Removing hook configuration..."

    # Remove our specific hooks
    UPDATED=$(cat "$SETTINGS_FILE" | jq '
        if .hooks then
            .hooks |= (
                del(.SessionStart[] | select(.hooks[].command | contains("memory-hooks"))) |
                del(.PreCompact[] | select(.hooks[].command | contains("memory-hooks"))) |
                del(.SessionEnd[] | select(.hooks[].command | contains("memory-hooks"))) |
                # Clean up empty arrays
                with_entries(select(.value | length > 0))
            ) |
            # Remove hooks key if empty
            if .hooks == {} then del(.hooks) else . end
        else
            .
        end
    ')

    echo "$UPDATED" > "$SETTINGS_FILE"
fi

# Remove hook scripts
if [[ -d "$HOOKS_DIR" ]]; then
    echo "Removing hook scripts..."
    rm -rf "$HOOKS_DIR"
fi

# Remove commands
if [[ -f "$COMMANDS_DIR/churn.md" ]]; then
    echo "Removing commands..."
    rm -f "$COMMANDS_DIR/churn.md"
fi

# Ask about memory files
echo ""
read -p "Preserve memory files (self-model, flagged, index)? [Y/n] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Removing memory files..."
    rm -rf "$MEMORY_DIR"

    # Also remove project-specific memory directories
    if [[ -d "$CLAUDE_DIR/projects" ]]; then
        find "$CLAUDE_DIR/projects" -type d -name "memory" -exec rm -rf {} + 2>/dev/null || true
    fi
else
    echo "Preserving memory files at: $MEMORY_DIR/"
fi

# Restore backup if exists
if [[ -f "$SETTINGS_FILE.backup" ]]; then
    echo ""
    read -p "Restore original settings.json from backup? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mv "$SETTINGS_FILE.backup" "$SETTINGS_FILE"
        echo "Settings restored from backup."
    else
        rm -f "$SETTINGS_FILE.backup"
    fi
fi

echo ""
echo "Uninstallation complete!"
