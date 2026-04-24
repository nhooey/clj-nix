#!/usr/bin/env bash
# Regenerate garnix.yaml from the current bats files in test/e2e/.
#
# Run this whenever you add or remove an .bats file. The action set in
# nix/garnix.nix is derived dynamically via builtins.readDir, but
# garnix.yaml is committed as a static file so it can be reviewed in
# PRs without evaluating Nix.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OUT=garnix.yaml
HEADER_END_PATTERN='^actions:'

# Preserve the file header (everything up to and including "actions:").
header_lines=$(grep -n "$HEADER_END_PATTERN" "$OUT" | head -1 | cut -d: -f1)
head -n "$header_lines" "$OUT" > "$OUT.tmp"

# tests-network is fixed.
cat >> "$OUT.tmp" <<'EOF'
  - on: push
    run: tests-network
    withRepoContents: true

EOF

# One action per bats file (sorted for deterministic output).
for f in $(find test/e2e -maxdepth 1 -name '*.bats' | sort); do
  base=$(basename "$f" .bats)
  cat >> "$OUT.tmp" <<EOF
  - on: push
    run: tests-e2e-${base}
    withRepoContents: true

EOF
done

# Trim trailing blank line.
sed -i.bak -e '$d' "$OUT.tmp" && rm -f "$OUT.tmp.bak"

mv "$OUT.tmp" "$OUT"
echo "Regenerated $OUT"
