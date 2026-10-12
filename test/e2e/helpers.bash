# vi: ft=sh
# Helpers shared by the bats files. Load with `load helpers`.

# Use podman if available, otherwise docker
container_runtime() {
  if command -v podman &> /dev/null; then
    echo "podman"
  else
    echo "docker"
  fi
}

# Build a flake output without a result link, and log its output path
# Usage: nix_build_and_log <flake-ref>
nix_build_and_log() {
  nix build "$1" --no-link --print-out-paths >> "$DERIVATIONS"
}

# Build a flake output, create ./result, and log its output path
# Usage: nix_build_with_result <flake-ref>
nix_build_with_result() {
  nix build "$1" --print-out-paths >> "$DERIVATIONS"
}

# Build and log a flake output, then run it with the given arguments
# Usage: nix_run_and_log <flake-ref> [args...]
nix_run_and_log() {
  local flake_ref="$1"
  shift
  nix_build_and_log "$flake_ref"
  nix run "$flake_ref" -- "$@"
}

# Set and export project_dir (a per-file temp dir) and cljnix_dir (this repo)
# Usage: setup_temp_project_vars [<dir-name>]
setup_temp_project_vars() {
  project_dir="$BATS_FILE_TMPDIR/${1:-clj-nix_project}"
  export project_dir
  cljnix_dir=$(dirname "$(dirname "$BATS_TEST_DIRNAME")")
  export cljnix_dir
}

# Render <template> into $project_dir/flake.nix with clj-nix at <cljnix-url>,
# cd into $project_dir and lock the flake
# Usage: init_project_flake <cljnix-url> <template>
init_project_flake() {
  echo "cljnixUrl: $1" | mustache "$2" > "$project_dir/flake.nix"
  cd "$project_dir" || return 1
  nix flake lock
}
