#!/bin/bash

# Fix conflicts in golden test files by accepting the current version
echo "Fixing conflicts in golden test files..."

# Find all conflicted golden files and accept the current version
find Tests/CompilerCoreTests/GoldenCases -name "*.golden" -exec grep -l "<<<<<<<" {} \; | while read file; do
    echo "Fixing $file"
    # Accept the current version (remove conflict markers and keep our version)
    sed -i '' '/^<<<<<<< HEAD/,/^=======$/d' "$file"
    sed -i '' '/^>>>>>>> .*$/d' "$file"
    git add "$file"
done

echo "Fixed all golden test conflicts"
