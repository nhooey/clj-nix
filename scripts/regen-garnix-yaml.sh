#!/usr/bin/env bash
# Regenerate garnix.yaml's `actions:` section from the action set
# defined in nix/garnix.nix.
#
# Source of truth: the e2eGroups list (and tests-network) in
# nix/garnix.nix, exposed on the flake as `garnixActionNames`. This
# script just translates that list into garnix.yaml entries.
#
# Run after editing e2eGroups (e.g. adding a new bats file).

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OUT=garnix.yaml
HEADER_END_PATTERN='^actions:'

# Preserve the file header (everything up to and including "actions:").
header_lines=$(grep -n "$HEADER_END_PATTERN" "$OUT" | head -1 | cut -d: -f1)
head -n "$header_lines" "$OUT" > "$OUT.tmp"
echo "" >> "$OUT.tmp"

# Pull action names from the flake. Single source of truth.
mapfile -t actions < <(nix eval --json .#garnixActionNames.x86_64-linux | jq -r '.[]')

if [ "${#actions[@]}" -eq 0 ]; then
  echo "Refusing to write empty action list — flake eval returned nothing." >&2
  rm -f "$OUT.tmp"
  exit 1
fi

for name in "${actions[@]}"; do
  cat >> "$OUT.tmp" <<EOF
  - on: push
    run: ${name}
    withRepoContents: true

EOF
done

# Trim trailing blank line.
sed -i.bak -e '$d' "$OUT.tmp" && rm -f "$OUT.tmp.bak"

mv "$OUT.tmp" "$OUT"
echo "Regenerated $OUT with ${#actions[@]} action(s)."
