#!/bin/bash
# CodePacker Uninstaller

set -euo pipefail

echo "╔══════════════════════════════════════╗"
echo "║      CodePacker Uninstaller          ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Remove engine
echo "→ Removing packing engine..."
rm -rf "$HOME/.local/share/CodePacker"

# Remove CLI symlink
echo "→ Removing CLI command..."
rm -f "$HOME/.local/bin/codepacker"

# Remove Quick Actions
echo "→ Removing Quick Actions..."
rm -rf "$HOME/Library/Services/CodePacker — Pack to Clipboard.workflow"
rm -rf "$HOME/Library/Services/CodePacker — Pack to File.workflow"
rm -rf "$HOME/Library/Services/CodePacker — Pack Compact.workflow"

# Remove support data
echo "→ Removing app data..."
rm -rf "$HOME/Library/Application Support/CodePacker"

# Refresh
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo ""
echo "✓ CodePacker has been completely removed."
