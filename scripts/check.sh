#!/bin/zsh
# Builds and runs every test, and shows only the lines that matter.
# Pass a filter to run some tests only, for example: scripts/check.sh LibraryPushTests

set -o pipefail
root="${0:A:h:h}"

swift build --package-path "$root" 2>&1 | grep -E "error:|warning: .*\.swift|Build complete" || exit 1

if [[ -n "$1" ]]; then
    swift test --package-path "$root" --filter "$1" 2>&1 | grep -E "Test run with|✘|failed|error:|recorded an issue"
else
    swift test --package-path "$root" 2>&1 | grep -E "Test run with|✘|failed|error:|recorded an issue"
fi
exit 0
