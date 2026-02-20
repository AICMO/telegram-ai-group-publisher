#!/bin/bash
# Rescue uncommitted work on CI failure.
# Creates a branch with any uncommitted state changes and pushes it.

set -e

BRANCH_NAME="rescue/$(date +%Y%m%d-%H%M%S)"

# Check if there are any changes to rescue
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    echo "No uncommitted changes to rescue."
    exit 0
fi

echo "Rescuing uncommitted work to branch: $BRANCH_NAME"

git checkout -b "$BRANCH_NAME"
git add -A
git commit -m "rescue: uncommitted state from failed pipeline run

Automatic rescue commit from CI failure.
$(date -u +%Y-%m-%dT%H:%M:%SZ)"

git push origin "$BRANCH_NAME"
echo "Rescued to branch: $BRANCH_NAME"
