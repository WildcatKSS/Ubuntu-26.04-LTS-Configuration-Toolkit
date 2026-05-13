#!/usr/bin/env bash
# Setup git hooks for the toolkit development

set -euo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TOOLKIT_ROOT"

echo "Setting up git hooks for version and changelog enforcement..."

# Install pre-commit hook
if [ -d .git/hooks ]; then
    ln -sf ../../scripts/hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo "✅ Pre-commit hook installed"
    echo ""
    echo "This hook will:"
    echo "  - Require VERSION file update for code changes"
    echo "  - Validate semantic versioning format"
    echo "  - Recommend CHANGELOG.md updates"
    echo ""
    echo "To bypass (not recommended): git commit --no-verify"
else
    echo "❌ Not a git repository or .git/hooks does not exist"
    exit 1
fi

echo ""
echo "Setup complete! Development hooks are active."
echo ""
echo "Next steps:"
echo "  1. Read CONTRIBUTING.md for development guidelines"
echo "  2. When making code changes:"
echo "     - Update VERSION file (MAJOR.MINOR.PATCH)"
echo "     - Update CHANGELOG.md under [Unreleased]"
echo "     - Commit normally (hook will validate)"
