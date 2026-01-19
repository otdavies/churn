#!/bin/bash
# Gentler Memory for Claude Code - Installer
# One-click setup for the memory system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
MEMORY_DIR="$CLAUDE_DIR/memory"
HOOKS_DIR="$CLAUDE_DIR/memory-hooks"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "Installing Gentler Memory for Claude Code..."
echo ""

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# Create directories
echo "Creating directories..."
mkdir -p "$MEMORY_DIR"
mkdir -p "$HOOKS_DIR"
mkdir -p "$COMMANDS_DIR"

# Copy templates
echo "Installing templates..."
cp "$SCRIPT_DIR/templates/self-model.md" "$MEMORY_DIR/"
cp "$SCRIPT_DIR/templates/global-index.md" "$MEMORY_DIR/"
cp "$SCRIPT_DIR/templates/flagged.md" "$MEMORY_DIR/"

# Copy hooks and make executable
echo "Installing hooks..."
cp "$SCRIPT_DIR/hooks/session_start.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/pre_compact.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/session_end.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/save.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/git.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/snapshot.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/trace.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/hooks/query.sh" "$HOOKS_DIR/"
chmod +x "$HOOKS_DIR"/*.sh

# Copy commands (skills)
echo "Installing commands..."
cp "$SCRIPT_DIR/commands/churn.md" "$COMMANDS_DIR/" || { echo "Error: Failed to copy churn.md"; exit 1; }
cp "$SCRIPT_DIR/commands/churn-done.md" "$COMMANDS_DIR/" || { echo "Warning: churn-done.md not found"; }
cp "$SCRIPT_DIR/commands/churn-push.md" "$COMMANDS_DIR/" || { echo "Warning: churn-push.md not found"; }
if [[ ! -f "$COMMANDS_DIR/churn.md" ]]; then
    echo "Error: churn.md not found at $COMMANDS_DIR/churn.md after copy"
    exit 1
fi

# Prepare hook configuration
HOOK_CONFIG='{
  "SessionStart": [{
    "hooks": [{
      "type": "command",
      "command": "bash ~/.claude/memory-hooks/session_start.sh",
      "timeout": 10
    }]
  }],
  "PreCompact": [{
    "hooks": [{
      "type": "command",
      "command": "bash ~/.claude/memory-hooks/pre_compact.sh",
      "timeout": 30
    }]
  }],
  "SessionEnd": [{
    "hooks": [{
      "type": "command",
      "command": "bash ~/.claude/memory-hooks/session_end.sh",
      "timeout": 10
    }]
  }]
}'

# Update settings.json
echo "Configuring hooks..."
if [[ -f "$SETTINGS_FILE" ]]; then
    # Backup existing settings
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup"

    # Merge hooks into existing settings
    EXISTING=$(cat "$SETTINGS_FILE")
    if echo "$EXISTING" | jq -e '.hooks' > /dev/null 2>&1; then
        # Has hooks section - merge
        UPDATED=$(echo "$EXISTING" | jq --argjson new "$HOOK_CONFIG" '.hooks = (.hooks // {}) * $new')
    else
        # No hooks section - add
        UPDATED=$(echo "$EXISTING" | jq --argjson new "$HOOK_CONFIG" '. + {hooks: $new}')
    fi
    echo "$UPDATED" > "$SETTINGS_FILE"
else
    # Create new settings file
    echo "{\"hooks\": $HOOK_CONFIG}" | jq '.' > "$SETTINGS_FILE"
fi

echo ""
echo "Installation complete!"
echo ""
echo "Memory system installed. On your next Claude Code session:"
echo "  - Self-model and flagged items loaded at start"
echo "  - /churn command for iterative refinement loops"
echo "  - save() to persist important context to working.md"
echo "  - Compaction uses ultra-compressed shorthand"
echo ""
echo "Locations:"
echo "  Global memory:  $MEMORY_DIR/"
echo "  Hook scripts:   $HOOKS_DIR/"
echo "  Commands:       $COMMANDS_DIR/"
echo "  Settings:       $SETTINGS_FILE"
echo ""
echo "To uninstall: bash $SCRIPT_DIR/uninstall.sh"
